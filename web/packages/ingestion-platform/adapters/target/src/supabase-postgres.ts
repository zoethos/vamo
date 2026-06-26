import { Client } from "pg";

import type { StagedCandidate } from "../../../core/src/index.js";
import type { ShipmentPlan } from "../../../core/src/shipment-plan.js";
import type { TargetProjectSpec } from "../../../spec/src/types.js";
import {
  planPostgresDryRun,
  type PgClientLike
} from "./postgres-dry-run.js";
import {
  evaluateSupabaseTargetSpecSecurity,
  hasBlockingSupabaseSecurityFindings,
  inspectSupabaseTargetSecurity,
  type SupabaseSecurityFinding
} from "./supabase-security-checks.js";

export interface SupabasePostgresDryRunInput {
  target: TargetProjectSpec;
  candidates: StagedCandidate[];
  connectionString?: string;
  client?: PgClientLike;
}

export interface SupabasePostgresDryRunResult {
  compatible: boolean;
  securityFindings: SupabaseSecurityFinding[];
  shipmentPlan: ShipmentPlan;
}

export async function planSupabasePostgresDryRun(
  input: SupabasePostgresDryRunInput
): Promise<SupabasePostgresDryRunResult> {
  const specFindings = evaluateSupabaseTargetSpecSecurity(input.target);
  if (hasBlockingSupabaseSecurityFindings(specFindings)) {
    return blockedResult(input.target, specFindings);
  }

  if (!input.client && !input.connectionString) {
    throw new Error("Supabase/Postgres dry-run requires a server-side connection string or client.");
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Supabase/Postgres dry-run client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  try {
    const securityFindings = await inspectSupabaseTargetSecurity({
      client,
      target: input.target
    });

    if (hasBlockingSupabaseSecurityFindings(securityFindings)) {
      return blockedResult(input.target, securityFindings);
    }

    const shipmentPlan = await planPostgresDryRun({
      client,
      target: input.target,
      candidates: input.candidates
    });

    return {
      compatible: shipmentPlan.compatible,
      securityFindings,
      shipmentPlan
    };
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

function blockedResult(
  target: TargetProjectSpec,
  securityFindings: SupabaseSecurityFinding[]
): SupabasePostgresDryRunResult {
  return {
    compatible: false,
    securityFindings,
    shipmentPlan: {
      mode: "dry_run",
      targetId: target.id,
      targetProject: target.name,
      compatible: false,
      items: [],
      incompatibilities: []
    }
  };
}
