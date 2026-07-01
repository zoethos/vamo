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

assert(
  platformPackage.name === "@confluendo/ingestion-platform",
  `platform package name is ${platformPackage.name}, expected @confluendo/ingestion-platform`
);

assert(
  sitePackage.dependencies?.["@confluendo/ingestion-platform"] === "*",
  "site app must depend on @confluendo/ingestion-platform as the provider package"
);

assert(
  !sitePackage.dependencies?.["@vamo/ingestion-platform"],
  "site app must not depend on @vamo/ingestion-platform"
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

console.log("Confluendo boundary audit");
console.log(`- package: ${platformPackage.name}`);
console.log("- site dependency: @confluendo/ingestion-platform");
console.log(`- scanned text files: ${textFiles.length}`);
console.log(`- scanned platform runtime files: ${platformRuntimeFiles.length}`);

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
