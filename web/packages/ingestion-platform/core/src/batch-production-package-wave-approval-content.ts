/**
 * Server-side staged content hash enrichment for production package-wave approval.
 */

import {
  buildBatchWaveUnitScope,
  type BatchWaveUnitScope
} from "./batch-staging-canary-wave-candidates.js";
import { hashProductionPackageCandidateContent } from "./production-package-content-hash.js";
import type { BatchProductionPackageWaveApprovalPlan } from "./batch-production-package-wave-policy.js";
import type { BatchQueueItem } from "./batch-queue-read-model.js";
import type { StagedCandidate } from "./pipeline-runner.js";

export type ProductionPackageWaveCandidateLoader = (input: {
  unit: BatchQueueItem;
  scope: BatchWaveUnitScope;
}) => Promise<StagedCandidate[]>;

export async function enrichProductionPackageWaveApprovalPlanWithStagedContentHashes(input: {
  plan: BatchProductionPackageWaveApprovalPlan;
  queueItemsByUnitKey: Record<string, BatchQueueItem>;
  loadCandidates: ProductionPackageWaveCandidateLoader;
}): Promise<BatchProductionPackageWaveApprovalPlan> {
  const selectedUnits = [];
  for (const selected of input.plan.selectedUnits) {
    const queueItem = input.queueItemsByUnitKey[selected.item.unitKey];
    const scope = queueItem ? buildBatchWaveUnitScope(queueItem) : null;
    if (!queueItem || !scope) {
      throw new Error(
        `Cannot compute staged content hash for unit "${selected.item.unitKey}" — queue scope is unavailable.`
      );
    }
    const candidates = await input.loadCandidates({ unit: queueItem, scope });
    if (candidates.length === 0) {
      throw new Error(
        `Cannot compute staged content hash for unit "${selected.item.unitKey}" — no deliverable candidates were resolved.`
      );
    }
    const stagedContentHash = hashProductionPackageCandidateContent(candidates);
    selectedUnits.push({
      ...selected,
      stagingEvidence: {
        ...selected.stagingEvidence,
        stagedContentHash
      }
    });
  }
  return {
    ...input.plan,
    selectedUnits
  };
}
