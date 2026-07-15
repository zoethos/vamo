#!/usr/bin/env node

// IP-18.8.15 trusted hosted-artifact-store preflight.
// This command calls HeadBucket only. It never reads or writes snapshot objects.

import {
  parseSnapshotArtifactStoreConfig,
  verifySnapshotArtifactStoreAccess
} from "../dist/adapters/artifact/src/index.js";

const parsed = parseSnapshotArtifactStoreConfig({
  env: process.env,
  requireHostedStore: true
});

if (!parsed.ok) {
  console.error("Snapshot artifact store configuration blocked:");
  for (const block of parsed.blocks) {
    console.error(`  - [${block.code}] ${block.message}`);
  }
  process.exit(1);
}

try {
  const verified = await verifySnapshotArtifactStoreAccess(parsed.config);
  console.log("Snapshot artifact store preflight passed");
  console.log(`- provider: ${verified.provider === "supabase_storage" ? "Supabase Storage" : "S3-compatible"}`);
  console.log(`- bucket: ${verified.bucket}`);
  console.log(`- region: ${verified.region}`);
  console.log("- operation: HeadBucket only; no snapshot objects were read or written.");
} catch (error) {
  const message = error instanceof Error ? error.message : "Unknown artifact store access failure.";
  console.error(`Snapshot artifact store preflight failed: ${message}`);
  const code =
    typeof error === "object" && error !== null && "code" in error && typeof error.code === "string"
      ? error.code
      : undefined;
  if (code === "artifact_storage_access_denied") {
    console.error(
      "Next: in this Supabase project, confirm Storage S3 is enabled and generate a new S3 access-key pair. Copy the exact region shown on Storage > Configuration > S3 into the matching trusted-worker environment file."
    );
  } else if (code === "artifact_storage_unavailable") {
    console.error(
      "Next: confirm the Supabase project reference, S3 protocol setting, and exact region shown on Storage > Configuration > S3. Then retry with a newly generated key pair from that same project."
    );
  }
  process.exit(1);
}
