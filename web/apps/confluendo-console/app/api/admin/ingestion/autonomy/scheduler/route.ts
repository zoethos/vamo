import { NextResponse, type NextRequest } from "next/server";
import {
  authorizeHostedAutonomySchedulerRequest,
  parseHostedAutonomySchedulerConfig,
  runAutonomyScheduler,
  type HostedAutonomySchedulerEnv
} from "@confluendo/ingestion-platform/core";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Hosted autonomy scheduler endpoint (IP-18.7.5).
 *
 * Server-only scheduled runner. It composes the existing bounded scheduler and
 * does not introduce a new write path. It never executes live staging writes or
 * consumer apply. Production package delivery is passed through only when both
 * policy and explicit server env gates allow it.
 */
export async function GET(request: NextRequest) {
  return handleHostedSchedulerRequest(request);
}

export async function POST(request: NextRequest) {
  return handleHostedSchedulerRequest(request);
}

async function handleHostedSchedulerRequest(request: NextRequest) {
  const auth = authorizeHostedAutonomySchedulerRequest({
    headers: request.headers,
    configuredSecret:
      process.env.CONFLUENDO_AUTONOMY_SCHEDULER_SECRET ?? process.env.CRON_SECRET
  });
  if (!auth.ok) {
    return NextResponse.json(
      { ok: false, code: auth.code, error: auth.message },
      { status: auth.status }
    );
  }

  if (process.env.VAMO_STAGING_CANARY_APP_DATABASE_URL?.trim()) {
    return NextResponse.json(
      {
        ok: false,
        code: "staging_canary_dsn_present",
        error:
          "Hosted autonomy refuses to run while VAMO_STAGING_CANARY_APP_DATABASE_URL is set."
      },
      { status: 503 }
    );
  }

  const schedulerEnv: HostedAutonomySchedulerEnv = {
    INGESTION_CONTROL_DATABASE_URL: process.env.INGESTION_CONTROL_DATABASE_URL,
    CONFLUENDO_AUTONOMY_SCHEDULER_PROJECT_KEY:
      process.env.CONFLUENDO_AUTONOMY_SCHEDULER_PROJECT_KEY,
    CONFLUENDO_AUTONOMY_SCHEDULER_POLICY_KEY:
      process.env.CONFLUENDO_AUTONOMY_SCHEDULER_POLICY_KEY,
    CONFLUENDO_AUTONOMY_SCHEDULER_TARGET_KEY:
      process.env.CONFLUENDO_AUTONOMY_SCHEDULER_TARGET_KEY,
    CONFLUENDO_AUTONOMY_SCHEDULER_AGENT_ID:
      process.env.CONFLUENDO_AUTONOMY_SCHEDULER_AGENT_ID,
    CONFLUENDO_AUTONOMY_SCHEDULER_REASON:
      process.env.CONFLUENDO_AUTONOMY_SCHEDULER_REASON,
    CONFLUENDO_AUTONOMY_SCHEDULER_MAX_CYCLES:
      process.env.CONFLUENDO_AUTONOMY_SCHEDULER_MAX_CYCLES,
    CONFLUENDO_AUTONOMY_SCHEDULER_INTERVAL_MS:
      process.env.CONFLUENDO_AUTONOMY_SCHEDULER_INTERVAL_MS,
    CONFIRM_CONFLUENDO_HOSTED_AUTONOMY_SCHEDULER:
      process.env.CONFIRM_CONFLUENDO_HOSTED_AUTONOMY_SCHEDULER,
    CONFIRM_CONFLUENDO_AUTONOMY_PRODUCTION_DELIVERY:
      process.env.CONFIRM_CONFLUENDO_AUTONOMY_PRODUCTION_DELIVERY,
    VAMO_PRODUCTION_INBOX_DATABASE_URL: process.env.VAMO_PRODUCTION_INBOX_DATABASE_URL,
    VAMO_PRODUCTION_INBOX_ENVIRONMENT: process.env.VAMO_PRODUCTION_INBOX_ENVIRONMENT
  };
  const parsed = parseHostedAutonomySchedulerConfig(schedulerEnv);
  if (!parsed.ok) {
    return NextResponse.json(
      { ok: false, decision: "blocked", blocks: parsed.blocks },
      { status: 503 }
    );
  }

  const { config } = parsed;

  try {
    const result = await runAutonomyScheduler({
      mode: "execute",
      connectionString: config.connectionString,
      projectKey: config.projectKey,
      policyKey: config.policyKey,
      targetKey: config.targetKey,
      agentId: config.agentId,
      reason: config.reason,
      maxCycles: config.maxCycles,
      intervalMs: config.intervalMs,
      productionInboxConnectionString: config.productionInboxConnectionString,
      productionInboxEnvironment: config.productionInboxEnvironment
    });

    return NextResponse.json({
      ok: true,
      executedAt: new Date().toISOString(),
      projectKey: config.projectKey,
      policyKey: config.policyKey,
      productionDeliveryEnabled: config.productionDeliveryEnabled,
      result
    });
  } catch (error) {
    console.error("Hosted autonomy scheduler failed", error);
    const message =
      error instanceof Error ? error.message : "Hosted autonomy scheduler failed.";
    return NextResponse.json(
      { ok: false, decision: "failed", error: message },
      { status: 500 }
    );
  }
}
