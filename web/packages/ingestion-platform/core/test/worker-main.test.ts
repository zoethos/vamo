import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { after, describe, it } from "node:test";

import {
  runWorkerHarness,
  type WorkerHarnessConfig
} from "../src/worker-main.js";
import type { PipelineCheckpoint } from "../src/pipeline-runner.js";

const pipelinePath = resolve("fixtures/imported/vamo-place-intelligence/pipeline.yaml");
const fixtureRoot = resolve("fixtures/imported/vamo-place-intelligence");
const tempDirs: string[] = [];

after(async () => {
  await Promise.all(tempDirs.map((dir) => rm(dir, { recursive: true, force: true })));
});

describe("container worker harness", () => {
  it("persists checkpoint, lease, summary, and events after a bounded run", async () => {
    const stateDir = await makeStateDir();
    const summary = await runTestWorker({
      stateDir,
      maxBatches: 1
    });

    assert.equal(summary.status, "stopped_after_batch_limit");
    assert.equal(summary.checkpoint?.cursorValue.last, 2);
    assert.equal(summary.checkpoint?.processedCount, 2);
    assert.equal(summary.candidatesStaged, 2);
    assert.equal(summary.deadLetters, 0);

    assert.equal(existsSync(join(stateDir, "checkpoint.json")), true);
    assert.equal(existsSync(join(stateDir, "events.jsonl")), true);
    assert.equal(existsSync(join(stateDir, "lease.json")), true);
    assert.equal(existsSync(join(stateDir, "summary.json")), true);

    const checkpoint = await readJson<PipelineCheckpoint>(join(stateDir, "checkpoint.json"));
    assert.equal(checkpoint.cursorValue.last, 2);

    const lease = await readJson<{ status: string; releaseReason?: string }>(
      join(stateDir, "lease.json")
    );
    assert.equal(lease.status, "released");
    assert.equal(lease.releaseReason, "max_batches_reached");

    const events = await readEvents(stateDir);
    assert.equal(events.some((event) => event.eventType === "checkpoint_committed"), true);
    assert.equal(
      events.some((event) => event.eventType === "worker_stopped_after_batch_limit"),
      true
    );
  });

  it("resumes from the last committed checkpoint and completes the imported snapshot", async () => {
    const stateDir = await makeStateDir();
    await runTestWorker({
      stateDir,
      maxBatches: 1
    });

    const resumed = await runTestWorker({
      stateDir
    });

    assert.equal(resumed.status, "succeeded");
    assert.equal(resumed.exitReason, "source_exhausted");
    assert.equal(resumed.checkpoint?.cursorValue.last, 38);
    assert.equal(resumed.checkpoint?.processedCount, 38);
    assert.equal(resumed.candidatesStaged, 34);
    assert.equal(resumed.deadLetters, 2);
    assert.equal(resumed.policyEvaluations > 0, true);

    const events = await readEvents(stateDir);
    assert.equal(events.some((event) => event.eventType === "worker_resumed"), true);
    assert.equal(events.some((event) => event.eventType === "worker_completed"), true);
  });

  it("pauses before the next batch without deleting checkpoint state", async () => {
    const stateDir = await makeStateDir();
    await runTestWorker({
      stateDir,
      maxBatches: 1
    });
    await writeFile(
      join(stateDir, "command.json"),
      `${JSON.stringify({ command: "pause", reason: "operator pause smoke" })}\n`,
      "utf8"
    );

    const paused = await runTestWorker({
      stateDir
    });

    assert.equal(paused.status, "paused");
    assert.equal(paused.exitReason, "operator pause smoke");
    assert.equal(paused.batchesProcessed, 0);
    assert.equal(paused.checkpoint?.cursorValue.last, 2);

    const lease = await readJson<{ status: string; releaseReason?: string }>(
      join(stateDir, "lease.json")
    );
    assert.equal(lease.status, "released");
    assert.equal(lease.releaseReason, "operator_pause");

    const checkpoint = await readJson<PipelineCheckpoint>(join(stateDir, "checkpoint.json"));
    assert.equal(checkpoint.cursorValue.last, 2);

    const events = await readEvents(stateDir);
    assert.equal(
      events.some(
        (event) =>
          event.eventType === "command_received" &&
          event.signal === "operator_pause" &&
          event.payload.reason === "operator pause smoke"
      ),
      true
    );
  });

  it("records a failure signal when the command file is invalid", async () => {
    const stateDir = await makeStateDir();
    await writeFile(
      join(stateDir, "command.json"),
      `${JSON.stringify({ command: "reset", reason: "not supported here" })}\n`,
      "utf8"
    );

    const failed = await runTestWorker({
      stateDir
    });

    assert.equal(failed.status, "failed");
    assert.match(failed.exitReason, /Unsupported worker command/);

    const lease = await readJson<{ status: string; releaseReason?: string }>(
      join(stateDir, "lease.json")
    );
    assert.equal(lease.status, "released");
    assert.equal(lease.releaseReason, "worker_failed");

    const events = await readEvents(stateDir);
    assert.equal(
      events.some(
        (event) =>
          event.eventType === "worker_failed" &&
          event.signal === "worker_failure" &&
          String(event.message).includes("Unsupported worker command")
      ),
      true
    );
  });
});

async function makeStateDir(): Promise<string> {
  const stateDir = await mkdtemp(join(tmpdir(), "ingestion-worker-"));
  tempDirs.push(stateDir);
  return stateDir;
}

function runTestWorker(
  overrides: Partial<WorkerHarnessConfig> & Pick<WorkerHarnessConfig, "stateDir">
): ReturnType<typeof runWorkerHarness> {
  return runWorkerHarness({
    pipelinePath,
    sourceRoot: fixtureRoot,
    workerId: "test-worker-01",
    batchSize: 2,
    ...overrides
  });
}

async function readEvents(stateDir: string): Promise<Array<Record<string, any>>> {
  const text = await readFile(join(stateDir, "events.jsonl"), "utf8");
  return text
    .trim()
    .split("\n")
    .filter((line) => line.trim().length > 0)
    .map((line) => JSON.parse(line) as Record<string, any>);
}

async function readJson<T>(path: string): Promise<T> {
  return JSON.parse(await readFile(path, "utf8")) as T;
}
