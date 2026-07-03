import type { PipelineSpec } from "../../spec/src/types.js";

export type PolicyDecision = "allow" | "deny" | "review";

export interface PolicyEvaluation {
  policyKey: string;
  decision: PolicyDecision;
  reasonCode?: string;
  reasonMessage?: string;
  subjectKey?: string;
  evidence: Record<string, unknown>;
}

export interface EvaluateRecordPolicyInput {
  pipeline: PipelineSpec;
  record: Record<string, unknown>;
  recordKey: string;
}

export function evaluateRecordPolicy(input: EvaluateRecordPolicyInput): PolicyEvaluation[] {
  const evaluations: PolicyEvaluation[] = [
    evaluateStorageRights(input),
    ...evaluateQualityGates(input)
  ];

  const fixtureDeny = getPath(input.record, "policy.deny");
  if (fixtureDeny === true) {
    evaluations.push({
      policyKey: "fixture.policy.deny",
      decision: "deny",
      reasonCode: readString(input.record, "policy.reasonCode") ?? "fixture_policy_denied",
      reasonMessage: readString(input.record, "policy.reasonMessage") ?? "Fixture row policy denied.",
      subjectKey: input.recordKey,
      evidence: {
        recordKey: input.recordKey
      }
    });
  }

  return evaluations;
}

export function hasPolicyDenial(evaluations: PolicyEvaluation[]): boolean {
  return evaluations.some((evaluation) => evaluation.decision === "deny");
}

function evaluateStorageRights(input: EvaluateRecordPolicyInput): PolicyEvaluation {
  const mediaBytesPresent =
    getPath(input.record, "media.bytesBase64") !== undefined ||
    getPath(input.record, "media.bytes") !== undefined ||
    getPath(input.record, "mediaBytes") !== undefined ||
    getPath(input.record, "media_bytes") !== undefined;
  const contentPresent =
    getPath(input.record, "content.html") !== undefined ||
    getPath(input.record, "content.body") !== undefined;
  const license = input.pipeline.source.license;

  if (mediaBytesPresent && !license.canStoreMediaBytes) {
    return {
      policyKey: "source.storage_rights",
      decision: "deny",
      reasonCode: "media_bytes_not_cacheable",
      reasonMessage: "Source row contains media bytes, but the source license does not allow storing media bytes.",
      subjectKey: input.recordKey,
      evidence: {
        sourceId: input.pipeline.source.id,
        license: license.name,
        canStoreMediaBytes: license.canStoreMediaBytes
      }
    };
  }

  if (contentPresent && !license.canStoreContent) {
    return {
      policyKey: "source.storage_rights",
      decision: "deny",
      reasonCode: "content_not_cacheable",
      reasonMessage: "Source row contains reusable content, but the source license does not allow storing content.",
      subjectKey: input.recordKey,
      evidence: {
        sourceId: input.pipeline.source.id,
        license: license.name,
        canStoreContent: license.canStoreContent
      }
    };
  }

  if (input.pipeline.policyRequests.storeFacts && !license.canStoreFacts) {
    return {
      policyKey: "source.storage_rights",
      decision: "deny",
      reasonCode: "facts_not_cacheable",
      reasonMessage: "Pipeline requests durable fact storage, but the source license does not allow it.",
      subjectKey: input.recordKey,
      evidence: {
        sourceId: input.pipeline.source.id,
        license: license.name,
        canStoreFacts: license.canStoreFacts
      }
    };
  }

  return {
    policyKey: "source.storage_rights",
    decision: "allow",
    subjectKey: input.recordKey,
    evidence: {
      sourceId: input.pipeline.source.id,
      license: license.name
    }
  };
}

function evaluateQualityGates(input: EvaluateRecordPolicyInput): PolicyEvaluation[] {
  return input.pipeline.qualityGates.map((gate) => {
    if (gate.type === "attribution_present") {
      const attribution =
        input.pipeline.source.license.attribution || readString(input.record, "attribution");
      if (!attribution && gate.severity === "block") {
        return {
          policyKey: `quality.${gate.id}`,
          decision: "deny",
          reasonCode: "missing_attribution",
          reasonMessage: "Attribution is required before staging this row.",
          subjectKey: input.recordKey,
          evidence: {
            gateId: gate.id
          }
        };
      }
    }

    if (gate.type === "live_only_source_guard" && input.pipeline.source.license.liveOnly) {
      return {
        policyKey: `quality.${gate.id}`,
        decision: "deny",
        reasonCode: "live_only_source",
        reasonMessage: "Live-only sources cannot produce reusable staged candidates.",
        subjectKey: input.recordKey,
        evidence: {
          gateId: gate.id,
          sourceId: input.pipeline.source.id
        }
      };
    }

    if (gate.type === "allowed_values" || gate.type === "enum") {
      const allowedValues = gate.values ?? [];
      const field = gate.field;
      const rawValue = field ? getPath(input.record, field) : undefined;
      const normalizedValue = typeof rawValue === "string" ? rawValue.trim() : undefined;
      const allowed = normalizedValue !== undefined && allowedValues.includes(normalizedValue);

      if (!allowed && gate.severity === "block") {
        return {
          policyKey: `quality.${gate.id}`,
          decision: "deny",
          reasonCode: "value_not_allowed",
          reasonMessage: field
            ? `Value for "${field}" must be one of: ${allowedValues.join(", ")}.`
            : "Quality gate is missing the field to validate.",
          subjectKey: input.recordKey,
          evidence: {
            gateId: gate.id,
            gateType: gate.type,
            field,
            value: rawValue,
            allowedValues
          }
        };
      }
    }

    return {
      policyKey: `quality.${gate.id}`,
      decision: "allow",
      subjectKey: input.recordKey,
      evidence: {
        gateId: gate.id,
        gateType: gate.type
      }
    };
  });
}

function readString(record: Record<string, unknown>, path: string): string | undefined {
  const value = getPath(record, path);
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function getPath(record: Record<string, unknown>, path: string): unknown {
  return path.split(".").reduce<unknown>((current, segment) => {
    if (typeof current !== "object" || current === null || Array.isArray(current)) {
      return undefined;
    }

    return (current as Record<string, unknown>)[segment];
  }, record);
}
