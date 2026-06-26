// Import a consumer contract bundle into the platform as a pinned snapshot.
//
// A consumer (e.g. Vamo) owns its contract in its own repo. This script copies a
// snapshot into fixtures/imported/<consumer>-<profile>/, validates it with the
// spec kernel, and records provenance (source repo + commit + content hashes) so
// the platform never reads the consumer repo at runtime.
//
// Usage:
//   npm --workspace @vamo/ingestion-platform run import:contract -- --from <bundle-dir> [--out <dir>]
//
// Requires a prior build (the npm script runs `build` first); it imports the
// compiled spec kernel from dist/.

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync
} from "node:fs";
import { basename, dirname, join, relative, resolve } from "node:path";

import {
  parseConsumerContractManifest,
  parsePipelineSpec,
  parseTargetProjectSpec
} from "../dist/spec/src/index.js";

function getArg(name, fallback) {
  const index = process.argv.indexOf(name);
  if (index >= 0 && index + 1 < process.argv.length) {
    return process.argv[index + 1];
  }
  return fallback;
}

function fail(label, errors) {
  console.error(`Import failed (${label}):`);
  for (const error of errors) {
    console.error(`  - [${error.code}] ${error.path}: ${error.message}`);
  }
  process.exit(1);
}

function git(fromDir, args) {
  const result = spawnSync("git", ["-C", fromDir, ...args], { encoding: "utf8" });
  return result.status === 0 ? result.stdout.trim() : undefined;
}

function sha256(filePath) {
  return createHash("sha256").update(readFileSync(filePath)).digest("hex");
}

const fromArg = getArg("--from");
if (!fromArg) {
  console.error(
    "Usage: import-consumer-contract --from <bundle-dir> [--out <dir>]"
  );
  process.exit(1);
}

const fromDir = resolve(fromArg);
const outRoot = resolve(getArg("--out", "fixtures/imported"));

const manifestPath = join(fromDir, "manifest.yaml");
if (!existsSync(manifestPath)) {
  console.error(`No manifest.yaml found in ${fromDir}`);
  process.exit(1);
}

const manifestResult = parseConsumerContractManifest(readFileSync(manifestPath, "utf8"));
if (!manifestResult.ok) {
  fail("manifest", manifestResult.errors);
}

const manifest = manifestResult.value;
const targetDir = join(outRoot, `${manifest.consumer}-${manifest.profile}`);

// Snapshot is fully regenerated each import so stale files never linger.
rmSync(targetDir, { recursive: true, force: true });
mkdirSync(targetDir, { recursive: true });

const exportPaths = [
  "manifest.yaml",
  manifest.exports.pipeline,
  manifest.exports.target,
  ...manifest.exports.fixtures
];

for (const relPath of exportPaths) {
  const sourceFile = join(fromDir, relPath);
  if (!existsSync(sourceFile)) {
    console.error(`Manifest references missing file: ${relPath}`);
    process.exit(1);
  }
  const destFile = join(targetDir, relPath);
  mkdirSync(dirname(destFile), { recursive: true });
  copyFileSync(sourceFile, destFile);
}

// Validate the imported snapshot with the spec kernel before we trust it.
const pipelineResult = parsePipelineSpec(
  readFileSync(join(targetDir, manifest.exports.pipeline), "utf8")
);
if (!pipelineResult.ok) {
  fail("pipeline", pipelineResult.errors);
}

const targetResult = parseTargetProjectSpec(
  readFileSync(join(targetDir, manifest.exports.target), "utf8")
);
if (!targetResult.ok) {
  fail("target", targetResult.errors);
}

const toplevel = git(fromDir, ["rev-parse", "--show-toplevel"]);
const commit = git(fromDir, ["rev-parse", "HEAD"]) ?? "unknown";
// Scope dirty check to the contract itself, not unrelated changes in the repo.
const contractDirty = Boolean(git(fromDir, ["status", "--porcelain", "--", "."]));
const contractPath = toplevel
  ? relative(toplevel, fromDir).replace(/\\/g, "/")
  : basename(fromDir);
const repo = toplevel ? basename(toplevel) : "unknown";

const files = exportPaths.map((relPath) => ({
  path: relPath.replace(/\\/g, "/"),
  sha256: sha256(join(targetDir, relPath))
}));

const metadata = {
  kind: "ingestion.import_metadata",
  consumer: manifest.consumer,
  profile: manifest.profile,
  contractVersion: manifest.version,
  source: {
    repo,
    commit,
    dirty: contractDirty,
    contractPath
  },
  importedAt: new Date().toISOString(),
  validation: {
    manifest: "ok",
    pipeline: "ok",
    target: "ok"
  },
  files
};

writeFileSync(
  join(targetDir, "IMPORT_METADATA.json"),
  `${JSON.stringify(metadata, null, 2)}\n`,
  "utf8"
);

console.log(
  `Imported ${manifest.consumer}/${manifest.profile} v${manifest.version} ` +
    `from ${repo}@${commit.slice(0, 12)}${contractDirty ? " (dirty)" : ""}`
);
console.log(`  -> ${relative(process.cwd(), targetDir).replace(/\\/g, "/")}`);
console.log(`  files: ${files.map((file) => file.path).join(", ")}`);
