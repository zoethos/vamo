/**
 * Published, metadata-only batch-plan contract refresh (IP-18.8.17).
 *
 * This is intentionally a narrow migration aid: it fills a missing source
 * taxonomy from a server-pinned published contract. It never accepts taxonomy
 * JSON from a browser and never permits an existing mapping to be overwritten.
 */

import type { AdminAssuranceLevel, AdminRole } from "./admin-auth.js";
import type { CommandActorType } from "./commands.js";
import {
  parseFsqSourceTaxonomy,
  type FsqSourceTaxonomyMapping
} from "./fsq-source-taxonomy.js";

export const PLAN_CONTRACT_REFRESH_CONFIRMATION_STATE = "refresh_published_contract" as const;

export interface PublishedPlanSourceTaxonomyContract {
  projectKey: string;
  planKey: string;
  sourceKey: string;
  sourceTaxonomy: FsqSourceTaxonomyMapping;
}

/**
 * The checked-in Vamo full-data plan is the published source of this mapping.
 * The matching test parses that plan and prevents this compact server catalog
 * from drifting from it until contract artifacts have their own registry.
 */
const VAMO_FULL_DATA_SOURCE_TAXONOMY: FsqSourceTaxonomyMapping = {
  provider: "fsq_os_places",
  fallbackConsumerCategory: "poi",
  mappings: [
    {
      providerCategoryIds: ["4d4b7105d754a06374d81259"],
      providerCategoryLabels: ["restaurant", "food", "café", "cafe"],
      consumerCategory: "restaurant",
      precedence: 100
    },
    {
      providerCategoryIds: [
        "4bf58dd8d48988d12d941735",
        "4bf58dd8d48988d181941735",
        "4deefb944765f83613cdba6e"
      ],
      providerCategoryLabels: ["monument / landmark", "museum", "historic site", "landmark"],
      consumerCategory: "landmark",
      precedence: 90
    },
    {
      providerCategoryIds: [
        "4d4b7105d754a06379d81259",
        "4bf58dd8d48988d1fe931735",
        "4bf58dd8d48988d1f6931735"
      ],
      providerCategoryLabels: [
        "travel and transportation",
        "bus station",
        "train station",
        "metro station",
        "airport"
      ],
      consumerCategory: "transport",
      precedence: 80
    },
    {
      providerCategoryIds: ["4d4b7104d754a06370d81259"],
      providerCategoryLabels: [
        "arts and entertainment",
        "nightlife spot",
        "shop & service",
        "outdoors & recreation"
      ],
      consumerCategory: "poi",
      precedence: 10
    }
  ]
};

const PUBLISHED_SOURCE_TAXONOMY_CONTRACTS: readonly PublishedPlanSourceTaxonomyContract[] = [
  {
    projectKey: "vamo",
    planKey: "vamo-eu-full-data-v1",
    sourceKey: "fsq-os-places-snapshot",
    sourceTaxonomy: VAMO_FULL_DATA_SOURCE_TAXONOMY
  }
];

export type BatchPlanContractRefreshBlockCode =
  | "missing_audit_reason"
  | "missing_actor_identity"
  | "actor_not_admin"
  | "fresh_step_up_required"
  | "mapping_already_configured"
  | "published_contract_unavailable";

export interface BatchPlanContractRefreshRequest {
  projectKey: string;
  auditReason: string;
  confirmedState: typeof PLAN_CONTRACT_REFRESH_CONFIRMATION_STATE;
}

export interface BatchPlanContractRefreshCardPresentation {
  title: string;
  statusLabel: string;
  tone: "good" | "watch" | "danger" | "neutral";
  description: string;
  planKey?: string;
  sourceKey?: string;
  mappingSummary?: string;
  safeguards: string[];
  canRefresh: boolean;
}

export function resolvePublishedPlanSourceTaxonomyContract(input: {
  projectKey: string;
  planKey: string;
  sourceKey: string;
}): PublishedPlanSourceTaxonomyContract | null {
  const contract = PUBLISHED_SOURCE_TAXONOMY_CONTRACTS.find(
    (candidate) =>
      candidate.projectKey === input.projectKey &&
      candidate.planKey === input.planKey &&
      candidate.sourceKey === input.sourceKey
  );
  return contract ? clonePublishedContract(contract) : null;
}

export function parseBatchPlanContractRefreshRequest(
  body: unknown
):
  | { ok: true; request: BatchPlanContractRefreshRequest }
  | { ok: false; error: string; code: string } {
  if (!isRecord(body)) {
    return { ok: false, error: "Request body must be a JSON object.", code: "invalid_body" };
  }
  const projectKey = readString(body.projectKey);
  const auditReason = readString(body.auditReason);
  const confirmedState = readString(body.confirmedState);
  if (!projectKey) {
    return { ok: false, error: "projectKey is required.", code: "project_key_required" };
  }
  if (!auditReason) {
    return { ok: false, error: "auditReason is required.", code: "audit_reason_required" };
  }
  if (confirmedState !== PLAN_CONTRACT_REFRESH_CONFIRMATION_STATE) {
    return {
      ok: false,
      error: "confirmedState must select the published contract refresh.",
      code: "confirmed_state_mismatch"
    };
  }
  return {
    ok: true,
    request: {
      projectKey,
      auditReason,
      confirmedState: PLAN_CONTRACT_REFRESH_CONFIRMATION_STATE
    }
  };
}

export function evaluateBatchPlanContractRefresh(input: {
  actor: {
    type: CommandActorType;
    id: string;
    role?: AdminRole;
    assuranceLevel?: AdminAssuranceLevel;
    stepUpFresh?: boolean;
  };
  auditReason: string;
  currentSourceTaxonomy: unknown;
  publishedContract: PublishedPlanSourceTaxonomyContract | null;
}):
  | { ok: true; auditReason: string; sourceTaxonomy: FsqSourceTaxonomyMapping }
  | { ok: false; blocks: Array<{ code: BatchPlanContractRefreshBlockCode; message: string }> } {
  const blocks: Array<{ code: BatchPlanContractRefreshBlockCode; message: string }> = [];
  if (!input.auditReason.trim()) {
    blocks.push({ code: "missing_audit_reason", message: "Plan contract refresh requires an audit reason." });
  }
  if (!input.actor.id.trim()) {
    blocks.push({ code: "missing_actor_identity", message: "Plan contract refresh requires a named operator." });
  }
  if (input.actor.type !== "operator" || input.actor.role !== "admin") {
    blocks.push({ code: "actor_not_admin", message: "Plan contract refresh requires an admin operator." });
  }
  if (input.actor.assuranceLevel !== "aal2" || input.actor.stepUpFresh !== true) {
    blocks.push({ code: "fresh_step_up_required", message: "Plan contract refresh requires a fresh AAL2 MFA check." });
  }
  if (hasSourceTaxonomyValue(input.currentSourceTaxonomy)) {
    blocks.push({ code: "mapping_already_configured", message: "This plan already has a source mapping; it will not be overwritten." });
  }
  if (!input.publishedContract) {
    blocks.push({ code: "published_contract_unavailable", message: "No published source mapping is available for this active plan." });
  }
  if (blocks.length > 0) {
    return { ok: false, blocks };
  }
  return {
    ok: true,
    auditReason: input.auditReason.trim(),
    sourceTaxonomy: input.publishedContract!.sourceTaxonomy
  };
}

export function presentBatchPlanContractRefreshCard(input: {
  projectKey?: string;
  planKey?: string;
  sourceKey?: string;
  currentSourceTaxonomy?: unknown;
  liveControlPlane: boolean;
}): BatchPlanContractRefreshCardPresentation {
  const publishedContract =
    input.projectKey && input.planKey && input.sourceKey
      ? resolvePublishedPlanSourceTaxonomyContract({
          projectKey: input.projectKey,
          planKey: input.planKey,
          sourceKey: input.sourceKey
        })
      : null;
  const configured = hasConfiguredSourceTaxonomy(input.currentSourceTaxonomy);
  const mappingValuePresent = hasSourceTaxonomyValue(input.currentSourceTaxonomy);
  const mappingSummary = publishedContract ? describeSourceTaxonomy(publishedContract.sourceTaxonomy) : undefined;
  const safeguards = [
    "Updates only the plan's source mapping metadata.",
    "Does not reseed scopes or change simulation, staging, delivery, or applied evidence.",
    "Requires an admin, fresh MFA, a confirmation, and an audit reason.",
    "Never overwrites a source mapping that is already configured."
  ];

  if (!input.liveControlPlane) {
    return {
      title: "Plan source mapping",
      statusLabel: "Live control plane required",
      tone: "neutral",
      description: "A live control-plane read is required before a plan contract can be refreshed.",
      planKey: input.planKey,
      sourceKey: input.sourceKey,
      mappingSummary,
      safeguards,
      canRefresh: false
    };
  }
  if (configured) {
    return {
      title: "Plan source mapping",
      statusLabel: "Configured",
      tone: "good",
      description: "The active plan already has a source mapping. Existing mappings are protected from replacement.",
      planKey: input.planKey,
      sourceKey: input.sourceKey,
      mappingSummary,
      safeguards,
      canRefresh: false
    };
  }
  if (mappingValuePresent) {
    return {
      title: "Plan source mapping",
      statusLabel: "Mapping needs review",
      tone: "danger",
      description:
        "The active plan contains an invalid source mapping. It is protected from automatic replacement; investigate it before commissioning a release.",
      planKey: input.planKey,
      sourceKey: input.sourceKey,
      safeguards,
      canRefresh: false
    };
  }
  if (!publishedContract) {
    return {
      title: "Plan source mapping",
      statusLabel: "No published mapping",
      tone: "danger",
      description: "This active plan has no source mapping and no matching published contract to apply.",
      planKey: input.planKey,
      sourceKey: input.sourceKey,
      safeguards,
      canRefresh: false
    };
  }
  return {
    title: "Plan source mapping",
    statusLabel: "Mapping required",
    tone: "watch",
    description:
      "Add the published FSQ-to-Vamo mapping so bounded source commissioning can validate provider categories without reseeding this historical queue.",
    planKey: input.planKey,
    sourceKey: input.sourceKey,
    mappingSummary,
    safeguards,
    canRefresh: true
  };
}

export function hasConfiguredSourceTaxonomy(value: unknown): boolean {
  return parseFsqSourceTaxonomy(value).ok;
}

export function hasSourceTaxonomyValue(value: unknown): boolean {
  return value !== undefined && value !== null;
}

function describeSourceTaxonomy(mapping: FsqSourceTaxonomyMapping): string {
  const categories = [...new Set(mapping.mappings.map((rule) => rule.consumerCategory))];
  return `FSQ categories map to ${categories.join(", ")}; other places map to ${mapping.fallbackConsumerCategory}.`;
}

function clonePublishedContract(
  contract: PublishedPlanSourceTaxonomyContract
): PublishedPlanSourceTaxonomyContract {
  return {
    ...contract,
    sourceTaxonomy: {
      ...contract.sourceTaxonomy,
      mappings: contract.sourceTaxonomy.mappings.map((mapping) => ({
        ...mapping,
        providerCategoryIds: [...mapping.providerCategoryIds],
        providerCategoryLabels: [...mapping.providerCategoryLabels]
      }))
    }
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}
