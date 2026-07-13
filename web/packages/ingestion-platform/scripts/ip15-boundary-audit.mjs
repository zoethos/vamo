#!/usr/bin/env node

import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const packageRoot = path.resolve(scriptDir, "..");
const webRoot = path.resolve(packageRoot, "..", "..");
const repoRoot = path.resolve(webRoot, "..");

const failures = [];

function assert(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

function readJson(file) {
  return JSON.parse(readFileSync(file, "utf8"));
}

const platformPackage = readJson(path.join(packageRoot, "package.json"));
const sitePackage = readJson(path.join(webRoot, "apps", "site", "package.json"));
const consolePackage = readJson(path.join(webRoot, "apps", "confluendo-console", "package.json"));

assert(
  platformPackage.name === "@confluendo/ingestion-platform",
  `platform package name is ${platformPackage.name}, expected @confluendo/ingestion-platform`
);

assert(
  consolePackage.name === "@confluendo/console",
  `console app name is ${consolePackage.name}, expected @confluendo/console`
);

assert(
  consolePackage.dependencies?.["@confluendo/ingestion-platform"] === "*",
  "console app must depend on @confluendo/ingestion-platform as the provider package"
);

assert(
  !sitePackage.dependencies?.["@vamo/ingestion-platform"],
  "site app must not depend on @vamo/ingestion-platform"
);

assert(
  !sitePackage.dependencies?.["@confluendo/ingestion-platform"],
  "Vamo site must not depend on @confluendo/ingestion-platform after the console carve-out"
);

assert(
  !sitePackage.dependencies?.["@confluendo/console"],
  "Vamo site must not depend on @confluendo/console; it should link/redirect to the console boundary"
);

const textFiles = walk(repoRoot).filter((file) => {
  const relative = toRepoRelative(file);
  if (relative.includes("/node_modules/") || relative.includes("/dist/") || relative.includes("/.next/")) {
    return false;
  }
  return /\.(cjs|css|html|js|json|mjs|md|sql|ts|tsx|yaml|yml)$/.test(file);
});

const staleNamespace = textFiles.filter((file) =>
  isExecutableSurface(file) && readFileSync(file, "utf8").includes("@vamo/ingestion-platform")
);

assert(
  staleNamespace.length === 0,
  `stale @vamo/ingestion-platform references remain:\n${staleNamespace.map(toRepoRelative).join("\n")}`
);

const siteRuntimeFiles = walk(path.join(webRoot, "apps", "site")).filter((file) => {
  const relative = toRepoRelative(file);
  if (relative.includes("/.next/") || relative.includes("/.turbo/")) {
    return false;
  }
  return /\.(js|mjs|ts|tsx|json)$/.test(file);
});

const siteProviderReferences = siteRuntimeFiles.filter((file) => {
  const source = readFileSync(file, "utf8");
  return source.includes("@confluendo/ingestion-platform") || source.includes("@confluendo/console");
});

assert(
  siteProviderReferences.length === 0,
  `Vamo site still references Confluendo packages:\n${siteProviderReferences.map(toRepoRelative).join("\n")}`
);

const consoleRuntimeFiles = walk(path.join(webRoot, "apps", "confluendo-console")).filter((file) => {
  const relative = toRepoRelative(file);
  if (relative.includes("/.next/") || relative.includes("/.turbo/")) {
    return false;
  }
  return /\.(js|mjs|ts|tsx)$/.test(file);
});

const consoleHostImports = consoleRuntimeFiles.filter((file) => {
  const source = readFileSync(file, "utf8");
  return /from\s+["'].*(?:apps\/site|@vamo\/site|Z:\\\\?vamo)/.test(source);
});

assert(
  consoleHostImports.length === 0,
  `console runtime files import the Vamo host:\n${consoleHostImports.map(toRepoRelative).join("\n")}`
);

const platformRuntimeFiles = walk(path.join(packageRoot)).filter((file) => {
  const relative = toRepoRelative(file);
  if (relative.includes("/dist/") || relative.includes("/test/") || relative.includes("/fixtures/")) {
    return false;
  }
  return /\.(js|mjs|ts)$/.test(file);
});

const forbiddenImports = platformRuntimeFiles.filter((file) => {
  const source = readFileSync(file, "utf8");
  return /from\s+["'].*(?:apps\/site|web\/apps|Z:\\\\?vamo)/.test(source);
});

assert(
  forbiddenImports.length === 0,
  `platform runtime files import host/Vamo paths:\n${forbiddenImports.map(toRepoRelative).join("\n")}`
);

const platformSrcRoots = [
  path.join(packageRoot, "core", "src"),
  path.join(packageRoot, "adapters", "source", "src"),
  path.join(packageRoot, "adapters", "target", "src"),
  path.join(packageRoot, "policy", "src"),
  path.join(packageRoot, "spec", "src")
];

const envFromTargetIdPatterns = [
  /targetId\s*\.\s*includes\s*\(\s*['"]staging['"]/,
  /targetId\s*\.\s*includes\s*\(\s*['"]production['"]/,
  /targetId\s*\.\s*endsWith\s*\(\s*['"]staging['"]/,
  /targetId\s*\.\s*endsWith\s*\(\s*['"]production['"]/,
  /targetId\s*\.\s*startsWith\s*\(\s*['"]staging['"]/,
  /targetId\s*\.\s*startsWith\s*\(\s*['"]production['"]/,
  /targetKey\s*\.\s*includes\s*\(\s*['"]staging['"]/,
  /targetKey\s*\.\s*includes\s*\(\s*['"]production['"]/,
  /targetKey\s*\.\s*endsWith\s*\(\s*['"]staging['"]/,
  /targetKey\s*\.\s*endsWith\s*\(\s*['"]production['"]/,
  /target_key\s*\.\s*includes\s*\(\s*['"]staging['"]/,
  /target_key\s*\.\s*includes\s*\(\s*['"]production['"]/
];

const envInferenceViolations = platformSrcRoots
  .flatMap((root) => walk(root))
  .filter((file) => /\.(js|mjs|ts)$/.test(file))
  .flatMap((file) => {
    const source = readFileSync(file, "utf8");
    const relative = toRepoRelative(file);
    const hits = envFromTargetIdPatterns
      .filter((pattern) => pattern.test(source))
      .map((pattern) => `${relative}: ${pattern}`);
    return hits;
  });

assert(
  envInferenceViolations.length === 0,
  `platform src must not infer environment from targetId/targetKey substrings:\n${envInferenceViolations.join("\n")}`
);

const fsqAcquisitionAdapter = path.join(
  packageRoot,
  "adapters",
  "source",
  "src",
  "fsq-os-places-catalog-acquire.ts"
);
const fsqAcquisitionSource = readFileSync(fsqAcquisitionAdapter, "utf8");
const platformSrcFiles = platformSrcRoots
  .flatMap((root) => walk(root))
  .filter((file) => /\.(js|mjs|ts)$/.test(file) && file !== fsqAcquisitionAdapter);

const providerFetchOutsideAdapter = platformSrcFiles.filter((file) => {
  const source = readFileSync(file, "utf8");
  return /\bfetch\s*\(/.test(source) || /catalog\.foursquare\.com/.test(source);
});

assert(
  providerFetchOutsideAdapter.length === 0,
  `provider networking must exist only in fsq-os-places-catalog-acquire.ts:\n${providerFetchOutsideAdapter
    .map(toRepoRelative)
    .join("\n")}`
);

const consoleRuntimeWithFsqToken = consoleRuntimeFiles.filter((file) => {
  const source = readFileSync(file, "utf8");
  return /FSQ_OS_PLACES_CATALOG_TOKEN/.test(source);
});

assert(
  consoleRuntimeWithFsqToken.length === 0,
  `console runtime must not reference FSQ_OS_PLACES_CATALOG_TOKEN:\n${consoleRuntimeWithFsqToken
    .map(toRepoRelative)
    .join("\n")}`
);

assert(
  !/\bFSQ_OS_PLACES_CATALOG_TOKEN\b/.test(fsqAcquisitionSource) ||
    fsqAcquisitionSource.includes('FSQ_OS_PLACES_CATALOG_TOKEN_ENV'),
  "FSQ acquisition adapter must reference the token env name only, never embed token values"
);

console.log("Confluendo boundary audit");
console.log(`- package: ${platformPackage.name}`);
console.log(`- console app: ${consolePackage.name}`);
console.log("- console dependency: @confluendo/ingestion-platform");
console.log("- site dependency: none (redirect/link boundary only)");
console.log(`- scanned text files: ${textFiles.length}`);
console.log(`- scanned site runtime files: ${siteRuntimeFiles.length}`);
console.log(`- scanned console runtime files: ${consoleRuntimeFiles.length}`);
console.log(`- scanned platform runtime files: ${platformRuntimeFiles.length}`);
console.log(`- scanned platform src roots for env-inference guard: ${platformSrcRoots.length}`);

if (failures.length > 0) {
  console.error("\nBoundary audit failed:");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("Boundary audit passed.");

function walk(root) {
  const files = [];
  for (const entry of readdirSync(root)) {
    const fullPath = path.join(root, entry);
    const stats = statSync(fullPath);
    if (stats.isDirectory()) {
      if (entry === ".git" || entry === "node_modules") {
        continue;
      }
      files.push(...walk(fullPath));
    } else if (stats.isFile()) {
      files.push(fullPath);
    }
  }
  return files;
}

function toRepoRelative(file) {
  return path.relative(repoRoot, file).replaceAll(path.sep, "/");
}

function isExecutableSurface(file) {
  const relative = toRepoRelative(file);
  if (relative.startsWith("docs/")) {
    return false;
  }
  if (relative === "web/packages/ingestion-platform/scripts/ip15-boundary-audit.mjs") {
    return false;
  }
  return true;
}
