/**
 * Actionable snapshot artifact storage errors (IP-18.8.12 remediation).
 */

export type SnapshotArtifactStorageErrorCode =
  | "artifact_key_unsafe"
  | "artifact_bundle_missing"
  | "artifact_bundle_incomplete"
  | "artifact_bundle_conflict"
  | "artifact_storage_access_denied"
  | "artifact_storage_unavailable";

export class SnapshotArtifactStorageError extends Error {
  readonly code: SnapshotArtifactStorageErrorCode;

  constructor(code: SnapshotArtifactStorageErrorCode, message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = "SnapshotArtifactStorageError";
    this.code = code;
  }
}

export function isSnapshotArtifactStorageError(
  error: unknown
): error is SnapshotArtifactStorageError {
  return error instanceof SnapshotArtifactStorageError;
}

export function isObjectNotFoundError(error: unknown): boolean {
  if (isSnapshotArtifactStorageError(error)) {
    return error.code === "artifact_bundle_missing";
  }
  if (typeof error !== "object" || error === null) {
    return false;
  }
  const name = "name" in error ? String(error.name) : "";
  const code = "code" in error ? String(error.code) : "";
  return (
    name === "NotFound" ||
    name === "NoSuchKey" ||
    code === "ENOENT" ||
    code === "NotFound" ||
    code === "NoSuchKey"
  );
}

export function isAccessDeniedError(error: unknown): boolean {
  if (typeof error !== "object" || error === null) {
    return false;
  }
  const name = "name" in error ? String(error.name) : "";
  const code = "code" in error ? String(error.code) : "";
  const httpStatusCode = readHttpStatusCode(error);
  return (
    name === "AccessDenied" ||
    name === "Forbidden" ||
    name === "SignatureDoesNotMatch" ||
    name === "InvalidAccessKeyId" ||
    name === "AuthorizationHeaderMalformed" ||
    code === "EACCES" ||
    code === "AccessDenied" ||
    code === "Forbidden" ||
    code === "SignatureDoesNotMatch" ||
    code === "InvalidAccessKeyId" ||
    code === "AuthorizationHeaderMalformed" ||
    code === "InvalidToken" ||
    httpStatusCode === 401 ||
    httpStatusCode === 403
  );
}

function readHttpStatusCode(error: object): number | undefined {
  if (!("$metadata" in error) || typeof error.$metadata !== "object" || error.$metadata === null) {
    return undefined;
  }
  const status = "httpStatusCode" in error.$metadata ? error.$metadata.httpStatusCode : undefined;
  return typeof status === "number" ? status : undefined;
}

export function isPreconditionFailedError(error: unknown): boolean {
  if (typeof error !== "object" || error === null) {
    return false;
  }
  const name = "name" in error ? String(error.name) : "";
  const code = "code" in error ? String(error.code) : "";
  return name === "PreconditionFailed" || code === "PreconditionFailed" || code === "EEXIST";
}

export function classifyArtifactReadError(error: unknown): SnapshotArtifactStorageError {
  if (isSnapshotArtifactStorageError(error)) {
    return error;
  }
  if (isObjectNotFoundError(error)) {
    return new SnapshotArtifactStorageError(
      "artifact_bundle_missing",
      "Snapshot artifact bundle file was not found.",
      { cause: error }
    );
  }
  if (isAccessDeniedError(error)) {
    return new SnapshotArtifactStorageError(
      "artifact_storage_access_denied",
      "Snapshot artifact storage access was denied.",
      { cause: error }
    );
  }
  return new SnapshotArtifactStorageError(
    "artifact_storage_unavailable",
    "Snapshot artifact storage is unavailable.",
    { cause: error }
  );
}
