/**
 * Hosted autonomy scheduler guard helpers (IP-18.7.5).
 *
 * Pure parsing/authorization helpers for a server-side cron/API route. No DB,
 * network, provider, staging, production inbox, or consumer apply access.
 */

import { timingSafeEqual } from "node:crypto";

import {
  DEFAULT_AUTONOMY_SCHEDULER_MAX_CYCLES,
  MAX_AUTONOMY_SCHEDULER_CYCLES
} from "./autonomy-scheduler.js";
import type { SnapshotArtifactStoreS3Config } from "./snapshot-artifact-store-config.js";
import { parseSnapshotArtifactStoreConfig } from "./snapshot-artifact-store-config.js";

export const HOSTED_AUTONOMY_SCHEDULER_CONFIRMATION = "YES";
export const HOSTED_AUTONOMY_PRODUCTION_DELIVERY_CONFIRMATION = "YES";
export const DEFAULT_HOSTED_AUTONOMY_SCHEDULER_AGENT_ID =
  "confluendo-hosted-autonomy-scheduler";
export const DEFAULT_HOSTED_AUTONOMY_SCHEDULER_REASON =
  "IP-18.7.5 hosted autonomy scheduler cycle";

export interface HostedAutonomySchedulerEnv {
  INGESTION_CONTROL_DATABASE_URL?: string;
  CONFLUENDO_AUTONOMY_SCHEDULER_PROJECT_KEY?: string;
  CONFLUENDO_AUTONOMY_SCHEDULER_POLICY_KEY?: string;
  CONFLUENDO_AUTONOMY_SCHEDULER_TARGET_KEY?: string;
  CONFLUENDO_AUTONOMY_SCHEDULER_BATCH_PLAN_KEY?: string;
  CONFLUENDO_AUTONOMY_SCHEDULER_AGENT_ID?: string;
  CONFLUENDO_AUTONOMY_SCHEDULER_REASON?: string;
  CONFLUENDO_AUTONOMY_SCHEDULER_MAX_CYCLES?: string;
  CONFLUENDO_AUTONOMY_SCHEDULER_INTERVAL_MS?: string;
  CONFIRM_CONFLUENDO_HOSTED_AUTONOMY_SCHEDULER?: string;
  CONFIRM_CONFLUENDO_AUTONOMY_PRODUCTION_DELIVERY?: string;
  VAMO_PRODUCTION_INBOX_DATABASE_URL?: string;
  VAMO_PRODUCTION_INBOX_ENVIRONMENT?: string;
  CONFLUENDO_SNAPSHOT_ARTIFACT_STORE?: string;
  CONFLUENDO_SNAPSHOT_ARTIFACT_S3_BUCKET?: string;
  CONFLUENDO_SNAPSHOT_ARTIFACT_S3_REGION?: string;
  CONFLUENDO_SNAPSHOT_ARTIFACT_S3_ENDPOINT?: string;
  CONFLUENDO_SNAPSHOT_ARTIFACT_S3_PREFIX?: string;
  CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF?: string;
  CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_BUCKET?: string;
  CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_REGION?: string;
  CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_PREFIX?: string;
  CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID?: string;
  CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY?: string;
}

export interface HostedAutonomySchedulerConfig {
  connectionString: string;
  projectKey: string;
  policyKey: string;
  targetKey?: string;
  batchPlanKey?: string;
  agentId: string;
  reason: string;
  maxCycles: number;
  intervalMs: number;
  productionDeliveryEnabled: boolean;
  productionInboxConnectionString?: string;
  productionInboxEnvironment?: string;
  artifactStoreConfig: SnapshotArtifactStoreS3Config;
}

export interface HostedAutonomySchedulerBlock {
  code: string;
  message: string;
}

export type HostedAutonomySchedulerConfigResult =
  | { ok: true; config: HostedAutonomySchedulerConfig }
  | { ok: false; blocks: HostedAutonomySchedulerBlock[] };

export interface HostedAutonomySchedulerHeaderReader {
  get(name: string): string | null;
}

export type HostedAutonomySchedulerAuthorizationResult =
  | { ok: true }
  | { ok: false; status: 401 | 503; code: string; message: string };

export function parseHostedAutonomySchedulerConfig(
  env: HostedAutonomySchedulerEnv
): HostedAutonomySchedulerConfigResult {
  const blocks: HostedAutonomySchedulerBlock[] = [];
  const connectionString = readTrimmed(env.INGESTION_CONTROL_DATABASE_URL);
  const projectKey = readTrimmed(env.CONFLUENDO_AUTONOMY_SCHEDULER_PROJECT_KEY);
  const policyKey = readTrimmed(env.CONFLUENDO_AUTONOMY_SCHEDULER_POLICY_KEY);
  const targetKey = readTrimmed(env.CONFLUENDO_AUTONOMY_SCHEDULER_TARGET_KEY);
  const batchPlanKey = readTrimmed(env.CONFLUENDO_AUTONOMY_SCHEDULER_BATCH_PLAN_KEY);
  const agentId =
    readTrimmed(env.CONFLUENDO_AUTONOMY_SCHEDULER_AGENT_ID) ??
    DEFAULT_HOSTED_AUTONOMY_SCHEDULER_AGENT_ID;
  const reason =
    readTrimmed(env.CONFLUENDO_AUTONOMY_SCHEDULER_REASON) ??
    DEFAULT_HOSTED_AUTONOMY_SCHEDULER_REASON;
  const maxCycles = parseOptionalPositiveInteger({
    name: "CONFLUENDO_AUTONOMY_SCHEDULER_MAX_CYCLES",
    value: env.CONFLUENDO_AUTONOMY_SCHEDULER_MAX_CYCLES,
    fallback: DEFAULT_AUTONOMY_SCHEDULER_MAX_CYCLES,
    min: 1,
    max: MAX_AUTONOMY_SCHEDULER_CYCLES,
    blocks
  });
  const intervalMs = parseOptionalPositiveInteger({
    name: "CONFLUENDO_AUTONOMY_SCHEDULER_INTERVAL_MS",
    value: env.CONFLUENDO_AUTONOMY_SCHEDULER_INTERVAL_MS,
    fallback: 0,
    min: 0,
    max: 60_000,
    blocks
  });
  const productionDeliveryEnabled =
    env.CONFIRM_CONFLUENDO_AUTONOMY_PRODUCTION_DELIVERY ===
    HOSTED_AUTONOMY_PRODUCTION_DELIVERY_CONFIRMATION;
  const productionInboxConnectionString = readTrimmed(env.VAMO_PRODUCTION_INBOX_DATABASE_URL);
  const productionInboxEnvironment = readTrimmed(env.VAMO_PRODUCTION_INBOX_ENVIRONMENT);

  if (env.CONFIRM_CONFLUENDO_HOSTED_AUTONOMY_SCHEDULER !== HOSTED_AUTONOMY_SCHEDULER_CONFIRMATION) {
    blocks.push({
      code: "hosted_scheduler_not_confirmed",
      message:
        "Set CONFIRM_CONFLUENDO_HOSTED_AUTONOMY_SCHEDULER=YES before hosted autonomy execution."
    });
  }
  if (!connectionString) {
    blocks.push({
      code: "control_database_missing",
      message: "INGESTION_CONTROL_DATABASE_URL is required."
    });
  }
  if (!projectKey) {
    blocks.push({
      code: "project_key_missing",
      message: "CONFLUENDO_AUTONOMY_SCHEDULER_PROJECT_KEY is required."
    });
  }
  if (!policyKey) {
    blocks.push({
      code: "policy_key_missing",
      message: "CONFLUENDO_AUTONOMY_SCHEDULER_POLICY_KEY is required."
    });
  }
  if (productionDeliveryEnabled) {
    if (!productionInboxConnectionString) {
      blocks.push({
        code: "production_inbox_database_missing",
        message:
          "VAMO_PRODUCTION_INBOX_DATABASE_URL is required when autonomous production delivery is enabled."
      });
    }
    if (productionInboxEnvironment !== "production") {
      blocks.push({
        code: "production_environment_not_proven",
        message:
          "VAMO_PRODUCTION_INBOX_ENVIRONMENT must be production when autonomous production delivery is enabled."
      });
    }
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  const artifactStoreParsed = parseSnapshotArtifactStoreConfig({
    env,
    requireHostedStore: true
  });
  if (!artifactStoreParsed.ok) {
    return {
      ok: false,
      blocks: artifactStoreParsed.blocks.map((block) => ({
        code: block.code,
        message: block.message
      }))
    };
  }
  if (artifactStoreParsed.config.kind !== "s3") {
    return {
      ok: false,
      blocks: [
        {
          code: "hosted_artifact_store_required",
          message:
            "Hosted autonomy requires a configured S3-compatible or Supabase Storage artifact store."
        }
      ]
    };
  }

  return {
    ok: true,
    config: {
      connectionString: connectionString!,
      projectKey: projectKey!,
      policyKey: policyKey!,
      targetKey,
      batchPlanKey,
      agentId,
      reason,
      maxCycles,
      intervalMs,
      productionDeliveryEnabled,
      productionInboxConnectionString: productionDeliveryEnabled
        ? productionInboxConnectionString
        : undefined,
      productionInboxEnvironment: productionDeliveryEnabled
        ? productionInboxEnvironment
        : undefined,
      artifactStoreConfig: artifactStoreParsed.config
    }
  };
}

export function authorizeHostedAutonomySchedulerRequest(input: {
  headers: HostedAutonomySchedulerHeaderReader;
  configuredSecret?: string;
}): HostedAutonomySchedulerAuthorizationResult {
  const expected = readTrimmed(input.configuredSecret);
  if (!expected) {
    return {
      ok: false,
      status: 503,
      code: "scheduler_secret_missing",
      message: "CONFLUENDO_AUTONOMY_SCHEDULER_SECRET is required."
    };
  }
  const candidates = [
    readBearerToken(input.headers.get("authorization")),
    readTrimmed(input.headers.get("x-cron-secret")),
    readTrimmed(input.headers.get("x-confluendo-scheduler-secret"))
  ].filter((value): value is string => Boolean(value));

  if (candidates.some((candidate) => safeEqual(candidate, expected))) {
    return { ok: true };
  }
  return {
    ok: false,
    status: 401,
    code: "scheduler_secret_invalid",
    message: "Hosted autonomy scheduler request is not authorized."
  };
}

function parseOptionalPositiveInteger(input: {
  name: string;
  value?: string;
  fallback: number;
  min: number;
  max: number;
  blocks: HostedAutonomySchedulerBlock[];
}): number {
  const raw = readTrimmed(input.value);
  if (!raw) return input.fallback;
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < input.min) {
    input.blocks.push({
      code: `${input.name.toLowerCase()}_invalid`,
      message: `${input.name} must be an integer >= ${input.min}.`
    });
    return input.fallback;
  }
  if (parsed > input.max) {
    input.blocks.push({
      code: `${input.name.toLowerCase()}_too_large`,
      message: `${input.name} must be <= ${input.max}.`
    });
    return input.fallback;
  }
  return parsed;
}

function readBearerToken(header: string | null): string | undefined {
  const value = readTrimmed(header);
  const match = value?.match(/^Bearer\s+(.+)$/i);
  return readTrimmed(match?.[1]);
}

function readTrimmed(value: string | null | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function safeEqual(a: string, b: string): boolean {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}
