export {
  CONTROL_SCHEMA_NAME,
  CONTROL_TABLES,
  controlTableRef,
  isControlTableName,
  type CheckpointScopeKey,
  type ControlTableName,
  type ControlTableRef,
  type IngestionRunStatus,
  type IngestionShipmentMode,
  type IngestionShipmentStatus,
  type IngestionTaskStatus,
  type ShipmentItemIdentity
} from "./control-models.js";
export {
  mapRecord,
  runFixturePipeline,
  runSourcePipeline,
  type DeadLetter,
  type IngestionEvent,
  type PipelineCheckpoint,
  type PipelineRunResult,
  type RunFixturePipelineInput,
  type RunSourcePipelineInput,
  type StagedCandidate
} from "./pipeline-runner.js";
export {
  buildShipmentDiff,
  recordIdentity,
  stableChecksum,
  type BuildShipmentDiffInput
} from "./diff.js";
export {
  expireStaleLeases,
  releaseActiveLeasesForTasks,
  type WorkerLeasePatch,
  type WorkerLeaseRow,
  type WorkerLeaseStatus
} from "./leases.js";
export {
  planTaskCommandTransition,
  type CommandTaskRow,
  type IngestionCommandKind,
  type PlanTaskTransitionInput,
  type TaskStatusPatch,
  type TaskTransitionError,
  type TaskTransitionOutcome,
  type TaskTransitionSkipped
} from "./run-state.js";
export {
  planIngestionCommand,
  type CommandActor,
  type CommandActorType,
  type CommandScope,
  type CommandStateSnapshot,
  type IngestionCommandAuditEvent,
  type IngestionCommandError,
  type IngestionCommandInput,
  type IngestionCommandPlan
} from "./commands.js";
export {
  applyPostgresIngestionCommand,
  type AppliedPostgresIngestionCommandResult,
  type ApplyPostgresIngestionCommandInput,
  type ControlCommandPgClientLike
} from "./control-command-api.js";
export {
  adminPrincipalAuditContext,
  authorizeAdminCommand,
  authorizeAdminDashboard,
  authorizeMachineCommand,
  MACHINE_TOKEN_COMMANDS,
  resolveAdminPrincipal,
  resolvePostgresAdminPrincipal,
  type AdminAssuranceLevel,
  type AdminAuthFailureCode,
  type AdminAuthPgClientLike,
  type AdminCommandAuthorizationInput,
  type AdminPrincipal,
  type AdminPrincipalResolution,
  type AdminPrincipalRow,
  type AdminPrincipalSession,
  type AdminPrincipalStatus,
  type AdminRole,
  type ResolvePostgresAdminPrincipalInput
} from "./admin-auth.js";
export {
  type ShipmentCandidateRow,
  type ShipmentOperation,
  type ShipmentPlan,
  type ShipmentPlanIncompatibility,
  type ShipmentPlanItem
} from "./shipment-plan.js";
export {
  configFromEnv,
  runWorkerHarness,
  type WorkerCommandFile,
  type WorkerExitStatus,
  type WorkerHarnessConfig,
  type WorkerRunSummary
} from "./worker-main.js";
export {
  rankTargetCandidates,
  scoreTargetCandidate,
  TARGET_SCORE_CRITERIA,
  type BlastRadiusFacts,
  type CheckpointabilityFacts,
  type CollisionFacts,
  type CollisionPolicy,
  type ConsumerValueFacts,
  type CostAndQuotaFacts,
  type DataQualityFacts,
  type ObservabilityFacts,
  type ScorecardCriterionResult,
  type SourceRightsFacts,
  type TargetCandidateInput,
  type TargetReadinessFacts,
  type TargetScoreCriterion,
  type TargetScorecard
} from "./target-scorecard.js";
export {
  buildScheduleProposal,
  deriveAdvisoryRationale,
  IP14_FORBIDDEN_SAFETY_MODES,
  TARGET_TIERS,
  type AiConfidence,
  type AiRationale,
  type ApprovalRequirement,
  type BuildScheduleProposalInput,
  type BuildScheduleProposalResult,
  type QuotaBudget,
  type RunWindow,
  type SafetyMode,
  type ScheduleProposal,
  type ScheduleProposalError,
  type ScheduleProposalErrorCode,
  type ScheduleScope,
  type StopConditions,
  type TargetTier
} from "./schedule-proposal.js";
export {
  buildScoutReport,
  evaluatePreflight,
  PROGRESSIVE_STAGES,
  runProgressiveDryRun,
  summarizeShipmentDiff,
  type CheckpointReport,
  type DryRunPlanRequest,
  type PreflightCheck,
  type PreflightReport,
  type ProgressiveDryRunDeps,
  type ProgressiveRunReport,
  type ProgressiveStage,
  type RowCounts,
  type RunProgressiveDryRunInput,
  type ScoutReport,
  type ShipmentDiffSummary,
  type StageResult,
  type StageStatus
} from "./progressive-run.js";
export {
  buildProgressiveRunView,
  sampleProgressiveRunSnapshot,
  sampleVamoProposal,
  type ProgressiveBacklogEntryInput,
  type ProgressiveBacklogRow,
  type ProgressiveRunSnapshot,
  type ProgressiveRunView,
  type ProgressiveWorkStatus
} from "./progressive-read-model.js";
export {
  evaluateStagingCanaryPromotion,
  summarizeWrite,
  STAGING_CANARY_FRESH_STEP_UP_WINDOW_MS,
  STAGING_CANARY_MAX_ROWS,
  type CanaryEnvironment,
  type EvaluateStagingCanaryPromotionInput,
  type EvaluateStagingCanaryPromotionResult,
  type StagingCanaryApprovalContext,
  type StagingCanaryApprover,
  type StagingCanaryBlock,
  type StagingCanaryBlockCode,
  type StagingCanaryBounds,
  type StagingCanaryPlan,
  type StagingCanaryWriteSummary
} from "./staging-canary-policy.js";
