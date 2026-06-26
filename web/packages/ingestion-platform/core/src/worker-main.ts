import { access, appendFile, mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { parsePipelineSpec } from "../../spec/src/index.js";
import {
  runFixturePipeline,
  type IngestionEvent,
  type PipelineCheckpoint
} from "./pipeline-runner.js";

export type WorkerExitStatus =
  | "succeeded"
  | "paused"
  | "shutdown"
  | "stopped_after_batch_limit"
  | "failed";

export interface WorkerHarnessConfig {
  pipelinePath: string;
  fixtureRoot?: string;
  stateDir: string;
  workerId: string;
  batchSize: number;
  maxBatches?: number;
  commandFile?: string;
  now?: () => Date;
}

export interface WorkerCommandFile {
  command: "pause" | "shutdown";
  reason?: string;
}

export interface WorkerRunSummary {
  status: WorkerExitStatus;
  workerId: string;
  pipelineId: string;
  batchesProcessed: number;
  candidatesStaged: number;
  deadLetters: number;
  policyEvaluations: number;
  checkpoint?: PipelineCheckpoint;
  exitReason: string;
  stateDir: string;
  updatedAt: string;
}

interface WorkerLedgerEvent extends IngestionEvent {
  timestamp: string;
  workerId: string;
}

interface WorkerLeaseFile {
  id: string;
  taskId: string;
  workerId: string;
  leaseToken: string;
  status: "active" | "released";
  acquiredAt: string;
  heartbeatAt: string;
  expiresAt: string;
  releasedAt?: string;
  releaseReason?: string;
}

const checkpointFileName = "checkpoint.json";
const eventsFileName = "events.jsonl";
const leaseFileName = "lease.json";
const summaryFileName = "summary.json";

export async function runWorkerHarness(
  config: WorkerHarnessConfig
): Promise<WorkerRunSummary> {
  if (config.batchSize <= 0) {
    throw new Error("Worker batch size must be greater than zero.");
  }

  const stateDir = resolve(config.stateDir);
  const commandFile = resolve(config.commandFile ?? resolve(stateDir, "command.json"));
  await mkdir(stateDir, { recursive: true });

  const pipelineResult = parsePipelineSpec(await readFile(config.pipelinePath, "utf8"));
  if (!pipelineResult.ok) {
    throw new Error(`Pipeline spec is invalid: ${JSON.stringify(pipelineResult.errors)}`);
  }

  const pipeline = pipelineResult.value;
  const now = config.now ?? (() => new Date());
  const lease = createLease({
    workerId: config.workerId,
    taskId: pipeline.id,
    now: now()
  });

  await writeJson(resolve(stateDir, leaseFileName), lease);
  await appendWorkerEvent(stateDir, config.workerId, now(), {
    eventType: "worker_started",
    severity: "info",
    message: "Fixture worker started.",
    payload: {
      pipelineId: pipeline.id,
      batchSize: config.batchSize
    }
  });
  await appendWorkerEvent(stateDir, config.workerId, now(), {
    eventType: "task_claimed",
    severity: "info",
    signal: "worker_lease_acquired",
    message: "Fixture task lease acquired.",
    payload: {
      taskId: pipeline.id,
      leaseToken: lease.leaseToken
    }
  });

  let checkpoint = await readJson<PipelineCheckpoint>(resolve(stateDir, checkpointFileName));
  if (checkpoint) {
    await appendWorkerEvent(stateDir, config.workerId, now(), {
      eventType: "worker_resumed",
      severity: "info",
      signal: "checkpoint_loaded",
      message: "Worker resumed from durable checkpoint.",
      payload: {
        checkpoint
      }
    });
  }

  let batchesProcessed = 0;
  let candidatesStaged = 0;
  let deadLetters = 0;
  let policyEvaluations = 0;

  try {
    for (;;) {
      const command = await readWorkerCommand(commandFile);
      if (command) {
        const status = command.command === "shutdown" ? "shutdown" : "paused";
        const releaseReason = command.command === "shutdown" ? "operator_shutdown" : "operator_pause";
        await appendWorkerEvent(stateDir, config.workerId, now(), {
          eventType: "command_received",
          severity: "info",
          signal: releaseReason,
          message: "Worker command received before starting next batch.",
          payload: {
            command: command.command,
            reason: command.reason,
            checkpoint
          }
        });
        await releaseLease(stateDir, lease, now(), releaseReason);
        return await writeSummary(stateDir, {
          status,
          workerId: config.workerId,
          pipelineId: pipeline.id,
          batchesProcessed,
          candidatesStaged,
          deadLetters,
          policyEvaluations,
          checkpoint,
          exitReason: command.reason ?? releaseReason,
          stateDir,
          updatedAt: now().toISOString()
        });
      }

      const previousCursor = checkpoint?.cursorValue.last;
      const result = await runFixturePipeline({
        pipeline,
        batchSize: config.batchSize,
        checkpoint,
        fixtureRoot: config.fixtureRoot ?? dirname(config.pipelinePath)
      });

      checkpoint = result.checkpoint;
      batchesProcessed += 1;
      candidatesStaged += result.candidates.length;
      deadLetters += result.deadLetters.length;
      policyEvaluations += result.policyEvaluations.length;

      await writeJson(resolve(stateDir, checkpointFileName), checkpoint);
      await appendWorkerEvents(stateDir, config.workerId, now, result.events);
      await heartbeatLease(stateDir, lease, now());

      if (
        result.checkpoint.cursorValue.last === previousCursor &&
        result.candidates.length === 0 &&
        result.deadLetters.length === 0 &&
        result.policyEvaluations.length === 0
      ) {
        await appendWorkerEvent(stateDir, config.workerId, now(), {
          eventType: "worker_completed",
          severity: "info",
          signal: "fixture_exhausted",
          message: "Fixture source produced no more rows.",
          payload: {
            checkpoint
          }
        });
        await releaseLease(stateDir, lease, now(), "completed");
        return await writeSummary(stateDir, {
          status: "succeeded",
          workerId: config.workerId,
          pipelineId: pipeline.id,
          batchesProcessed,
          candidatesStaged,
          deadLetters,
          policyEvaluations,
          checkpoint,
          exitReason: "fixture_exhausted",
          stateDir,
          updatedAt: now().toISOString()
        });
      }

      if (config.maxBatches !== undefined && batchesProcessed >= config.maxBatches) {
        await appendWorkerEvent(stateDir, config.workerId, now(), {
          eventType: "worker_stopped_after_batch_limit",
          severity: "info",
          signal: "batch_limit_reached",
          message: "Worker stopped after configured batch limit.",
          payload: {
            checkpoint,
            maxBatches: config.maxBatches
          }
        });
        await releaseLease(stateDir, lease, now(), "max_batches_reached");
        return await writeSummary(stateDir, {
          status: "stopped_after_batch_limit",
          workerId: config.workerId,
          pipelineId: pipeline.id,
          batchesProcessed,
          candidatesStaged,
          deadLetters,
          policyEvaluations,
          checkpoint,
          exitReason: "max_batches_reached",
          stateDir,
          updatedAt: now().toISOString()
        });
      }
    }
  } catch (error) {
    await appendWorkerEvent(stateDir, config.workerId, now(), {
      eventType: "worker_failed",
      severity: "error",
      signal: "worker_failure",
      message: error instanceof Error ? error.message : "Worker failed.",
      payload: {
        checkpoint
      }
    });
    await releaseLease(stateDir, lease, now(), "worker_failed");
    return await writeSummary(stateDir, {
      status: "failed",
      workerId: config.workerId,
      pipelineId: pipeline.id,
      batchesProcessed,
      candidatesStaged,
      deadLetters,
      policyEvaluations,
      checkpoint,
      exitReason: error instanceof Error ? error.message : "worker_failed",
      stateDir,
      updatedAt: now().toISOString()
    });
  }
}

export function configFromEnv(env: Record<string, string | undefined>): WorkerHarnessConfig {
  const stateDir = env.INGESTION_WORKER_STATE_DIR ?? ".ingestion-worker-state";
  return {
    pipelinePath:
      env.INGESTION_WORKER_PIPELINE ??
      "fixtures/imported/vamo-place-intelligence/pipeline.yaml",
    fixtureRoot: env.INGESTION_WORKER_FIXTURE_ROOT,
    stateDir,
    workerId: env.INGESTION_WORKER_ID ?? "fixture-worker-01",
    batchSize: parsePositiveInt(env.INGESTION_WORKER_BATCH_SIZE, 2),
    maxBatches: parseOptionalPositiveInt(env.INGESTION_WORKER_MAX_BATCHES),
    commandFile: env.INGESTION_WORKER_COMMAND_FILE ?? resolve(stateDir, "command.json")
  };
}

async function appendWorkerEvents(
  stateDir: string,
  workerId: string,
  now: () => Date,
  events: IngestionEvent[]
): Promise<void> {
  for (const event of events) {
    await appendWorkerEvent(stateDir, workerId, now(), event);
  }
}

async function appendWorkerEvent(
  stateDir: string,
  workerId: string,
  timestamp: Date,
  event: IngestionEvent
): Promise<void> {
  const ledgerEvent: WorkerLedgerEvent = {
    ...event,
    timestamp: timestamp.toISOString(),
    workerId
  };
  await appendFile(resolve(stateDir, eventsFileName), `${JSON.stringify(ledgerEvent)}\n`, "utf8");
}

async function readWorkerCommand(commandFile: string): Promise<WorkerCommandFile | undefined> {
  const command = await readJson<Partial<WorkerCommandFile>>(commandFile);
  if (!command) {
    return undefined;
  }

  if (command.command !== "pause" && command.command !== "shutdown") {
    throw new Error(`Unsupported worker command: ${String(command.command)}`);
  }

  return {
    command: command.command,
    reason: typeof command.reason === "string" ? command.reason : undefined
  };
}

async function heartbeatLease(
  stateDir: string,
  lease: WorkerLeaseFile,
  now: Date
): Promise<void> {
  await writeJson(resolve(stateDir, leaseFileName), {
    ...lease,
    status: "active",
    heartbeatAt: now.toISOString(),
    expiresAt: addSeconds(now, 30).toISOString()
  });
}

async function releaseLease(
  stateDir: string,
  lease: WorkerLeaseFile,
  now: Date,
  releaseReason: string
): Promise<void> {
  await writeJson(resolve(stateDir, leaseFileName), {
    ...lease,
    status: "released",
    heartbeatAt: now.toISOString(),
    expiresAt: addSeconds(now, 30).toISOString(),
    releasedAt: now.toISOString(),
    releaseReason
  });
}

function createLease(input: {
  workerId: string;
  taskId: string;
  now: Date;
}): WorkerLeaseFile {
  const acquiredAt = input.now.toISOString();
  return {
    id: `${input.workerId}:${input.taskId}`,
    taskId: input.taskId,
    workerId: input.workerId,
    leaseToken: `${input.workerId}:${input.now.getTime()}`,
    status: "active",
    acquiredAt,
    heartbeatAt: acquiredAt,
    expiresAt: addSeconds(input.now, 30).toISOString()
  };
}

async function writeSummary(
  stateDir: string,
  summary: WorkerRunSummary
): Promise<WorkerRunSummary> {
  await writeJson(resolve(stateDir, summaryFileName), summary);
  return summary;
}

async function readJson<T>(path: string): Promise<T | undefined> {
  try {
    await access(path);
  } catch {
    return undefined;
  }

  const text = await readFile(path, "utf8");
  if (text.trim().length === 0) {
    return undefined;
  }

  return JSON.parse(text) as T;
}

async function writeJson(path: string, value: unknown): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  const tempPath = `${path}.tmp`;
  await writeFile(tempPath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  await rename(tempPath, path);
}

function addSeconds(date: Date, seconds: number): Date {
  return new Date(date.getTime() + seconds * 1000);
}

function parsePositiveInt(value: string | undefined, fallback: number): number {
  if (value === undefined) {
    return fallback;
  }

  const parsed = Number(value);
  if (Number.isInteger(parsed) && parsed > 0) {
    return parsed;
  }

  throw new Error(`Expected positive integer, got: ${value}`);
}

function parseOptionalPositiveInt(value: string | undefined): number | undefined {
  if (value === undefined || value.trim().length === 0) {
    return undefined;
  }

  return parsePositiveInt(value, 1);
}

async function main(): Promise<void> {
  const summary = await runWorkerHarness(configFromEnv(process.env));
  process.stdout.write(`${JSON.stringify(summary)}\n`);
  if (summary.status === "failed") {
    process.exitCode = 1;
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  await main();
}
