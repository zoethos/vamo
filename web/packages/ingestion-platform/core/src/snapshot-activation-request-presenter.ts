/** Safe operator presenter for snapshot activation requests (IP-18.8.14). */
import type { SnapshotCommissionRequestRecord } from "./snapshot-commission-request.js";
import type { SnapshotActivationRequestRecord, SnapshotActivationRequestStatus } from "./snapshot-activation-request.js";

export interface SnapshotActivationCardPresentation {
  status: SnapshotActivationRequestStatus | "waiting";
  statusLabel: string;
  tone: "neutral" | "info" | "good" | "watch" | "danger";
  title: string;
  description: string;
  releaseId?: string;
  nextHumanAction: string;
  canCreateRequest: boolean;
  confirmationState: string;
  errorCode?: string;
  errorMessage?: string;
}

export function presentSnapshotActivationCard(input: {
  commissionRequest?: SnapshotCommissionRequestRecord | null;
  activationRequest?: SnapshotActivationRequestRecord | null;
  hasActiveRequest: boolean;
}): SnapshotActivationCardPresentation {
  const commission = input.commissionRequest;
  const request =
    input.activationRequest &&
    input.activationRequest.commissionRequestId === commission?.requestId &&
    input.activationRequest.releaseId === commission.registeredReleaseId
      ? input.activationRequest
      : undefined;
  const releaseId = commission?.status === "activation_pending" ? commission.registeredReleaseId : undefined;

  if (request) {
    switch (request.status) {
      case "requested":
        return active("requested", "Activation requested", "info", "Activation request recorded", "A trusted worker will verify the registered artifact and activate it. The browser does not access artifacts or bind releases.", request.releaseId);
      case "running":
        return active("running", "Activation running", "watch", "Trusted activation in progress", "The worker is verifying the artifact, binding the release, and reconciling the queue. Wait for the result; do not submit another request.", request.releaseId);
      case "activated":
        return active("activated", "Activated", "good", "Snapshot release active", "The verified release is bound to this batch plan and supply reconciliation has completed.", request.releaseId);
      case "failed":
        return {
          status: "failed",
          statusLabel: "Activation failed",
          tone: "danger",
          title: "Activation needs recovery",
          description: "The release was not activated. Review the worker result, correct the safe precondition, then submit a new activation request.",
          releaseId: request.releaseId,
          nextHumanAction: "Review the failure and submit a new request after the precondition is corrected.",
          canCreateRequest: !input.hasActiveRequest && Boolean(releaseId),
          confirmationState: "request_activation",
          errorCode: request.errorCode,
          errorMessage: request.errorMessage
        };
    }
  }

  if (!releaseId) {
    return {
      status: "waiting",
      statusLabel: "Awaiting release",
      tone: "neutral",
      title: "Snapshot activation",
      description: "A trusted commissioning worker must first register a verified release. Activation is always a separate operator-confirmed step.",
      nextHumanAction: "Wait for commissioning to reach Activation pending.",
      canCreateRequest: false,
      confirmationState: "request_activation"
    };
  }

  return {
    status: "waiting",
    statusLabel: "Ready for approval",
    tone: "info",
    title: "Activate verified snapshot release",
    description: "The registered release passed commissioning and is ready for a separately approved activation. Activation updates only the control-plane binding and queue supply.",
    releaseId,
    nextHumanAction: "Provide an audit reason, confirm activation, and let the trusted worker run the verified activation path.",
    canCreateRequest: !input.hasActiveRequest,
    confirmationState: "request_activation"
  };
}

function active(
  status: Extract<SnapshotActivationRequestStatus, "requested" | "running" | "activated">,
  statusLabel: string,
  tone: "info" | "watch" | "good",
  title: string,
  description: string,
  releaseId: string
): SnapshotActivationCardPresentation {
  return {
    status,
    statusLabel,
    tone,
    title,
    description,
    releaseId,
    nextHumanAction: status === "activated" ? "Review the refreshed queue and continue through the normal workflow." : "Wait for the trusted activation worker to complete.",
    canCreateRequest: false,
    confirmationState: "request_activation"
  };
}
