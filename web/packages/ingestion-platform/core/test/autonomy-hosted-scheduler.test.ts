import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";

import {
  authorizeHostedAutonomySchedulerRequest,
  parseHostedAutonomySchedulerConfig
} from "../src/autonomy-hosted-scheduler.js";

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..");
const webRoot = join(packageRoot, "..", "..");
const schedulerRoute = join(
  webRoot,
  "apps/confluendo-console/app/api/admin/ingestion/autonomy/scheduler/route.ts"
);

const hostedArtifactEnv = {
  CONFLUENDO_SNAPSHOT_ARTIFACT_STORE: "s3",
  CONFLUENDO_SNAPSHOT_ARTIFACT_S3_BUCKET: "confluendo-snapshot-artifacts",
  CONFLUENDO_SNAPSHOT_ARTIFACT_S3_REGION: "eu-west-1"
};

const baseEnv = {
  ...hostedArtifactEnv,
  INGESTION_CONTROL_DATABASE_URL: "postgresql://control.example/postgres",
  CONFLUENDO_AUTONOMY_SCHEDULER_PROJECT_KEY: "vamo",
  CONFLUENDO_AUTONOMY_SCHEDULER_POLICY_KEY: "vamo-eu-poi-staging-v1",
  CONFIRM_CONFLUENDO_HOSTED_AUTONOMY_SCHEDULER: "YES"
};

describe("parseHostedAutonomySchedulerConfig", () => {
  it("accepts the minimum hosted scheduler environment", () => {
    const parsed = parseHostedAutonomySchedulerConfig(baseEnv);
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.config.projectKey, "vamo");
    assert.equal(parsed.config.policyKey, "vamo-eu-poi-staging-v1");
    assert.equal(parsed.config.maxCycles, 10);
    assert.equal(parsed.config.intervalMs, 0);
    assert.equal(parsed.config.productionDeliveryEnabled, false);
    assert.equal(parsed.config.productionInboxConnectionString, undefined);
  });

  it("passes through an explicit batch plan key", () => {
    const parsed = parseHostedAutonomySchedulerConfig({
      ...baseEnv,
      CONFLUENDO_AUTONOMY_SCHEDULER_BATCH_PLAN_KEY: "vamo-eu-full-data-v1"
    });
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.config.batchPlanKey, "vamo-eu-full-data-v1");
  });

  it("requires an explicit hosted execution confirmation and policy identity", () => {
    const parsed = parseHostedAutonomySchedulerConfig({});
    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    const codes = parsed.blocks.map((block) => block.code);
    assert.ok(codes.includes("hosted_scheduler_not_confirmed"));
    assert.ok(codes.includes("control_database_missing"));
    assert.ok(codes.includes("project_key_missing"));
    assert.ok(codes.includes("policy_key_missing"));
  });

  it("requires production inbox proof only when autonomous production delivery is enabled", () => {
    const withoutProductionDelivery = parseHostedAutonomySchedulerConfig({
      ...baseEnv,
      VAMO_PRODUCTION_INBOX_DATABASE_URL: "postgresql://writer.example/postgres",
      VAMO_PRODUCTION_INBOX_ENVIRONMENT: "staging"
    });
    assert.equal(withoutProductionDelivery.ok, true);

    const withProductionDelivery = parseHostedAutonomySchedulerConfig({
      ...baseEnv,
      CONFIRM_CONFLUENDO_AUTONOMY_PRODUCTION_DELIVERY: "YES",
      VAMO_PRODUCTION_INBOX_DATABASE_URL: "postgresql://writer.example/postgres",
      VAMO_PRODUCTION_INBOX_ENVIRONMENT: "staging"
    });
    assert.equal(withProductionDelivery.ok, false);
    if (withProductionDelivery.ok) return;
    assert.equal(withProductionDelivery.blocks[0]?.code, "production_environment_not_proven");
  });

  it("validates bounded hosted scheduler cycle limits", () => {
    const parsed = parseHostedAutonomySchedulerConfig({
      ...baseEnv,
      CONFLUENDO_AUTONOMY_SCHEDULER_MAX_CYCLES: "0",
      CONFLUENDO_AUTONOMY_SCHEDULER_INTERVAL_MS: "60001"
    });
    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    const codes = parsed.blocks.map((block) => block.code);
    assert.ok(codes.includes("confluendo_autonomy_scheduler_max_cycles_invalid"));
    assert.ok(codes.includes("confluendo_autonomy_scheduler_interval_ms_too_large"));
  });
});

describe("authorizeHostedAutonomySchedulerRequest", () => {
  it("accepts bearer authorization", () => {
    const authorized = authorizeHostedAutonomySchedulerRequest({
      configuredSecret: "scheduler-secret",
      headers: headerReader({ authorization: "Bearer scheduler-secret" })
    });
    assert.equal(authorized.ok, true);
  });

  it("accepts cron secret headers", () => {
    const authorized = authorizeHostedAutonomySchedulerRequest({
      configuredSecret: "scheduler-secret",
      headers: headerReader({ "x-cron-secret": "scheduler-secret" })
    });
    assert.equal(authorized.ok, true);
  });

  it("rejects missing or invalid scheduler secrets", () => {
    const missing = authorizeHostedAutonomySchedulerRequest({
      headers: headerReader({ authorization: "Bearer scheduler-secret" })
    });
    assert.equal(missing.ok, false);
    if (!missing.ok) assert.equal(missing.status, 503);

    const invalid = authorizeHostedAutonomySchedulerRequest({
      configuredSecret: "scheduler-secret",
      headers: headerReader({ authorization: "Bearer wrong-secret" })
    });
    assert.equal(invalid.ok, false);
    if (!invalid.ok) assert.equal(invalid.status, 401);
  });
});

describe("hosted autonomy scheduler route artifact", () => {
  it("does not import artifact adapters from core modules", () => {
    const schedulerSource = readFileSync(join(packageRoot, "core/src/autonomy-hosted-scheduler.ts"), "utf8");
    assert.doesNotMatch(schedulerSource, /adapters\/artifact/);
  });

  it("uses the bounded scheduler and server-side env gates", () => {
    const routeSource = readFileSync(schedulerRoute, "utf8");
    assert.match(routeSource, /runAutonomyScheduler/);
    assert.match(routeSource, /authorizeHostedAutonomySchedulerRequest/);
    assert.match(routeSource, /parseHostedAutonomySchedulerConfig/);
    assert.match(routeSource, /CONFLUENDO_AUTONOMY_SCHEDULER_SECRET/);
    assert.match(routeSource, /CRON_SECRET/);
  });

  it("requires hosted S3 artifact store configuration", () => {
    const parsed = parseHostedAutonomySchedulerConfig({
      INGESTION_CONTROL_DATABASE_URL: "postgresql://control.example/postgres",
      CONFLUENDO_AUTONOMY_SCHEDULER_PROJECT_KEY: "vamo",
      CONFLUENDO_AUTONOMY_SCHEDULER_POLICY_KEY: "vamo-eu-poi-staging-v1",
      CONFIRM_CONFLUENDO_HOSTED_AUTONOMY_SCHEDULER: "YES"
    });
    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    assert.ok(parsed.blocks.some((block) => block.code === "hosted_artifact_store_missing"));
  });

  it("does not call live staging execution or consumer apply", () => {
    const routeSource = readFileSync(schedulerRoute, "utf8");
    assert.doesNotMatch(routeSource, /executeBatchStagingCanaryWave/);
    assert.doesNotMatch(routeSource, /executeProductionPackageConsumerApply/);
    assert.doesNotMatch(routeSource, /VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL/);
    assert.doesNotMatch(routeSource, /VAMO_STAGING_DATABASE_URL/);
    assert.match(routeSource, /VAMO_STAGING_CANARY_APP_DATABASE_URL/);
    assert.match(routeSource, /createSnapshotArtifactStore/);
    assert.match(routeSource, /@confluendo\/ingestion-platform\/adapters\/artifact/);
    assert.doesNotMatch(routeSource, /@aws-sdk\/client-s3/);
  });
});

function headerReader(values: Record<string, string>) {
  const lower = new Map(Object.entries(values).map(([key, value]) => [key.toLowerCase(), value]));
  return {
    get(name: string) {
      return lower.get(name.toLowerCase()) ?? null;
    }
  };
}
