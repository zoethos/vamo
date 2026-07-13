import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";

import { parseSnapshotReleaseManifest } from "../src/snapshot-release-manifest.js";
import {
  intakeVersionedSnapshot,
  isOutputPathInsideRepo,
  sha256Hex,
  writeSnapshotIntakeArtifacts
} from "../src/versioned-snapshot-intake.js";

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..");
const webRoot = join(packageRoot, "..", "..");
const repoRoot = join(webRoot, "..");
const fixtureDir = join(packageRoot, "fixtures/platform/ip18/snapshot-intake");
const intakeModulePath = join(packageRoot, "core/src/versioned-snapshot-intake.ts");
const manifestModulePath = join(packageRoot, "core/src/snapshot-release-manifest.ts");
const intakeScriptPath = join(packageRoot, "scripts/run-ip18-snapshot-intake.mjs");

function loadManifestWithSha(inputPath: string) {
  const inputContent = readFileSync(inputPath, "utf8");
  const manifestTemplate = readFileSync(join(fixtureDir, "manifest.yaml"), "utf8");
  const manifestRaw = manifestTemplate.replace(
    "PLACEHOLDER_SHA256",
    sha256Hex(inputContent)
  );
  const parsed = parseSnapshotReleaseManifest(manifestRaw);
  assert.equal(parsed.ok, true);
  return { manifest: parsed.manifest!, inputContent };
}

describe("parseSnapshotReleaseManifest", () => {
  it("accepts a complete snapshot release manifest", () => {
    const { manifest } = loadManifestWithSha(join(fixtureDir, "valid-input.jsonl"));
    assert.equal(manifest.sourceKey, "fsq-os-places-snapshot");
    assert.equal(manifest.sourceFormat, "normalized_jsonl");
    assert.equal(manifest.factStorageApproved, true);
  });

  it("rejects missing SHA-256 values", () => {
    const parsed = parseSnapshotReleaseManifest({
      kind: "ingestion.snapshot_release_manifest",
      sourceKey: "fsq-os-places-snapshot",
      sourceProvider: "fsq_os_places",
      releaseId: "bad",
      acquiredAt: "2026-07-01T12:00:00Z",
      provenanceUrl: "https://example.com",
      sourceAttribution: "FSQ Open Source Places",
      licenseIdentifier: "FSQ-OS-Places",
      factStorageApproved: true,
      retentionStatement: "retain",
      expectedSha256: "not-a-hash",
      sourceFormat: "normalized_jsonl",
      intendedConsumer: "vamo",
      intendedTarget: "vamo-place-intelligence"
    });
    assert.equal(parsed.ok, false);
  });
});

describe("intakeVersionedSnapshot", () => {
  it("accepts valid input deterministically and reports coverage from valid rows only", () => {
    const { manifest, inputContent } = loadManifestWithSha(join(fixtureDir, "valid-input.jsonl"));
    const first = intakeVersionedSnapshot({ manifest, inputContent, now: "2026-07-01T12:00:00Z" });
    const second = intakeVersionedSnapshot({ manifest, inputContent, now: "2026-07-01T12:00:00Z" });

    assert.equal(first.ok, true);
    assert.equal(first.accepted, true);
    assert.equal(second.ok, true);
    assert.equal(second.accepted, true);
    assert.equal(first.normalizedJsonl, second.normalizedJsonl);
    assert.equal(first.release.outputSha256, second.release.outputSha256);
    assert.equal(first.coverage.validRowCount, 2);
    assert.equal(first.coverage.invalidRowCount, 0);
    assert.deepEqual(first.coverage.byCountry, { france: 1, italy: 1 });
    assert.deepEqual(first.coverage.byPoiType, { landmark: 1, poi: 1 });
    assert.match(first.normalizedJsonl, /"source_row_id":1/);
    assert.match(first.normalizedJsonl, /rome-italy/);
    assert.ok(first.normalizedJsonl.indexOf("paris-france") < first.normalizedJsonl.indexOf("rome-italy"));
  });

  it("fails on checksum mismatch", () => {
    const { manifest, inputContent } = loadManifestWithSha(join(fixtureDir, "valid-input.jsonl"));
    const result = intakeVersionedSnapshot({
      manifest: {
        ...manifest,
        expectedSha256: "0".repeat(64)
      },
      inputContent
    });
    assert.equal(result.ok, false);
    assert.ok(result.blocks.includes("checksum_mismatch"));
  });

  it("surfaces invalid, duplicate, and rights issues and refuses release acceptance", () => {
    const { manifest, inputContent } = loadManifestWithSha(join(fixtureDir, "invalid-input.jsonl"));
    const result = intakeVersionedSnapshot({ manifest, inputContent });

    assert.equal(result.ok, true);
    assert.equal(result.accepted, false);
    assert.ok(result.blocks.includes("invalid_rows_present"));
    assert.ok(result.blocks.includes("duplicate_rows_present"));
    assert.ok(result.issues.some((issue) => issue.reason === "media_bytes_forbidden"));
    assert.ok(result.issues.some((issue) => issue.reason === "attribution_mismatch"));
    assert.ok(result.issues.some((issue) => issue.reason === "unknown_source_field"));
    assert.equal(result.coverage.validRowCount, 1);
  });

  it("rejects output directories inside the git worktree", () => {
    assert.equal(
      isOutputPathInsideRepo({
        outputDir: join(repoRoot, "tmp", "snapshot-release"),
        repoRoot
      }),
      true
    );
    assert.equal(
      isOutputPathInsideRepo({
        outputDir: join(tmpdir(), "confluendo-snapshot-release"),
        repoRoot
      }),
      false
    );
  });

  it("writes intake artifacts atomically outside the repo", () => {
    const { manifest, inputContent } = loadManifestWithSha(join(fixtureDir, "valid-input.jsonl"));
    const result = intakeVersionedSnapshot({ manifest, inputContent, now: "2026-07-01T12:00:00Z" });
    assert.equal(result.ok, true);
    assert.equal(result.accepted, true);

    const outputDir = mkdtempSync(join(tmpdir(), "snapshot-intake-test-"));
    try {
      writeSnapshotIntakeArtifacts({ outputDir, artifacts: result.artifacts });
      assert.ok(existsSync(join(outputDir, "source.jsonl")));
      assert.ok(existsSync(join(outputDir, "release.json")));
      assert.ok(existsSync(join(outputDir, "coverage-report.json")));
      assert.equal(readFileSync(join(outputDir, "source.jsonl"), "utf8"), result.normalizedJsonl);
      const release = JSON.parse(readFileSync(join(outputDir, "release.json"), "utf8"));
      assert.equal(release.outputSha256, result.release.outputSha256);
      const coverage = JSON.parse(readFileSync(join(outputDir, "coverage-report.json"), "utf8"));
      assert.equal(coverage.derivedFromValidRowsOnly, true);
      assert.equal(coverage.validRowCount, 2);
    } finally {
      rmSync(outputDir, { recursive: true, force: true });
    }
  });

  it("refuses intake when fact storage is not approved", () => {
    const { manifest, inputContent } = loadManifestWithSha(join(fixtureDir, "valid-input.jsonl"));
    const result = intakeVersionedSnapshot({
      manifest: { ...manifest, factStorageApproved: false },
      inputContent
    });
    assert.equal(result.ok, false);
    assert.ok(result.blocks.includes("fact_storage_not_approved"));
  });
});

describe("versioned snapshot intake artifact", () => {
  it("does not use network, provider clients, or database DSNs in the intake path", () => {
    const intakeSource = readFileSync(intakeModulePath, "utf8");
    const manifestSource = readFileSync(manifestModulePath, "utf8");
    const scriptSource = readFileSync(intakeScriptPath, "utf8");
    const combined = `${intakeSource}\n${manifestSource}\n${scriptSource}`;

    assert.doesNotMatch(combined, /\bfetch\s*\(/);
    assert.doesNotMatch(combined, /\bhttps?:\/\//);
    assert.doesNotMatch(combined, /from\s+["']pg["']/);
    assert.doesNotMatch(combined, /DATABASE_URL/);
  });

  it("requires explicit execute confirmation in the CLI", () => {
    const scriptSource = readFileSync(intakeScriptPath, "utf8");
    assert.match(scriptSource, /CONFIRM_CONFLUENDO_SNAPSHOT_INTAKE/);
    assert.match(scriptSource, /Preview only/);
    assert.doesNotMatch(scriptSource, /--execute[\s\S]*writeFileSync/);
  });
});
