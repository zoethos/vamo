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
  path.join(packageRoot, "adapters", "artifact", "src"),
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
  "fsq-os-places-portal-iceberg-acquire.ts"
);
const fsqPortalDuckDbRunner = path.join(
  packageRoot,
  "adapters",
  "source",
  "src",
  "fsq-os-places-portal-iceberg-duckdb.ts"
);
const s3ArtifactStoreAdapters = [
  path.join(packageRoot, "adapters", "artifact", "src", "s3-snapshot-artifact-store.ts"),
  path.join(packageRoot, "adapters", "artifact", "src", "create-snapshot-artifact-store.ts")
];
const fsqAcquisitionSource = readFileSync(fsqAcquisitionAdapter, "utf8");
const fsqDuckDbSource = readFileSync(fsqPortalDuckDbRunner, "utf8");
const platformSrcFiles = platformSrcRoots
  .flatMap((root) => walk(root))
  .filter(
    (file) =>
      /\.(js|mjs|ts)$/.test(file) &&
      file !== fsqAcquisitionAdapter &&
      file !== fsqPortalDuckDbRunner &&
      !s3ArtifactStoreAdapters.includes(file)
  );

const providerAccessOutsideAdapter = platformSrcFiles.filter((file) => {
  const source = readFileSync(file, "utf8");
  return (
    /\bfetch\s*\(/.test(source) ||
    /catalog\.foursquare\.com/.test(source) ||
    /catalog\.h3-hub\.foursquare\.com/.test(source) ||
    /@duckdb\/node-api/.test(source)
  );
});

assert(
  providerAccessOutsideAdapter.length === 0,
  `provider access must exist only in portal acquire/duckdb runner adapters:\n${providerAccessOutsideAdapter
    .map(toRepoRelative)
    .join("\n")}`
);

assert(
  !/catalog\.foursquare\.com/.test(fsqAcquisitionSource) &&
    !/catalog\.foursquare\.com/.test(fsqDuckDbSource),
  "FSQ acquisition adapter must not use the retired catalog.foursquare.com HTTP path"
);

assert(
  /catalog\.h3-hub\.foursquare\.com\/iceberg/.test(fsqAcquisitionSource) &&
    /places\.datasets\.places_os/.test(fsqAcquisitionSource),
  "FSQ acquisition adapter must target the Places Portal Iceberg endpoint and table"
);

assert(
  /@duckdb\/node-api/.test(fsqDuckDbSource) && !/@duckdb\/node-api/.test(fsqAcquisitionSource),
  "DuckDB import must live only in fsq-os-places-portal-iceberg-duckdb.ts"
);

const consoleRuntimeWithPortalSecrets = consoleRuntimeFiles.filter((file) => {
  const source = readFileSync(file, "utf8");
  return (
    /FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN/.test(source) ||
    /FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY/.test(source) ||
    /@duckdb\/node-api/.test(source)
  );
});

assert(
  consoleRuntimeWithPortalSecrets.length === 0,
  `console runtime must not reference FSQ Portal token, catalog service API key, or DuckDB:\n${consoleRuntimeWithPortalSecrets
    .map(toRepoRelative)
    .join("\n")}`
);

const consoleClientRuntimeFiles = consoleRuntimeFiles.filter((file) => {
  const relative = toRepoRelative(file);
  return !relative.includes("/app/api/");
});

const consoleRuntimeWithArtifactSecrets = consoleClientRuntimeFiles.filter((file) => {
  const source = readFileSync(file, "utf8");
  return (
    /CONFLUENDO_SNAPSHOT_ARTIFACT_S3_/.test(source) ||
    /CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_/.test(source) ||
    /AWS_SECRET_ACCESS_KEY/.test(source) ||
    /@aws-sdk\/client-s3/.test(source)
  );
});

assert(
  consoleRuntimeWithArtifactSecrets.length === 0,
  `console client runtime must not reference hosted artifact-store credentials or SDK:\n${consoleRuntimeWithArtifactSecrets
    .map(toRepoRelative)
    .join("\n")}`
);

const hostedSchedulerRoute = path.join(
  webRoot,
  "apps",
  "confluendo-console",
  "app",
  "api",
  "admin",
  "ingestion",
  "autonomy",
  "scheduler",
  "route.ts"
);
const hostedSchedulerRouteSource = readFileSync(hostedSchedulerRoute, "utf8");
const hostedSchedulerSuccessResponse =
  hostedSchedulerRouteSource.match(/return NextResponse\.json\(\{\s*ok: true,[\s\S]*?\}\);/)?.[0] ??
  "";
assert(
  hostedSchedulerRouteSource.includes("createSnapshotArtifactStore") &&
    hostedSchedulerRouteSource.includes("@confluendo/ingestion-platform/adapters/artifact"),
  "hosted scheduler route must resolve artifact store through the server-only adapter export"
);
assert(
  !/@aws-sdk\/client-s3/.test(hostedSchedulerRouteSource),
  "hosted scheduler route must not import @aws-sdk/client-s3 directly"
);
assert(
  !hostedSchedulerSuccessResponse.includes("artifactStoreConfig") &&
    !hostedSchedulerSuccessResponse.includes("bucket") &&
    !hostedSchedulerSuccessResponse.includes("s3://"),
  "hosted scheduler success response must not expose artifact-store config"
);

const stagingSnapshotCommissionWorkflow = path.join(
  repoRoot,
  ".github",
  "workflows",
  "confluendo-snapshot-commission-staging.yml"
);
const stagingSnapshotCommissionWorkflowSource = readFileSync(stagingSnapshotCommissionWorkflow, "utf8");
assert(
  /workflow_dispatch:/.test(stagingSnapshotCommissionWorkflowSource) &&
    !/\bpull_request:|\bpush:/.test(stagingSnapshotCommissionWorkflowSource),
  "staging snapshot commission workflow must be manually dispatched only"
);
assert(
  /environment:\s*\n\s+name:\s+confluendo-control-staging/.test(
    stagingSnapshotCommissionWorkflowSource
  ),
  "staging snapshot commission workflow must use the protected confluendo-control-staging environment"
);
assert(
  /ip18:snapshot-commission-worker/.test(stagingSnapshotCommissionWorkflowSource) &&
    /--require-hosted-artifact-store/.test(stagingSnapshotCommissionWorkflowSource),
  "staging snapshot commission workflow must run the trusted worker with a hosted artifact store"
);
assert(
  /secrets\.INGESTION_CONTROL_OWNER_DATABASE_URL/.test(stagingSnapshotCommissionWorkflowSource) &&
    /secrets\.FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN/.test(stagingSnapshotCommissionWorkflowSource) &&
    /secrets\.CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY/.test(
      stagingSnapshotCommissionWorkflowSource
    ) &&
    !/NEXT_PUBLIC_/.test(stagingSnapshotCommissionWorkflowSource),
  "staging snapshot commission workflow must use server-only protected secrets"
);

const stagingSnapshotActivationWorkflow = path.join(
  repoRoot,
  ".github",
  "workflows",
  "confluendo-snapshot-activation-staging.yml"
);
const stagingSnapshotActivationWorkflowSource = readFileSync(stagingSnapshotActivationWorkflow, "utf8");
assert(
  /workflow_dispatch:/.test(stagingSnapshotActivationWorkflowSource) &&
    !/\b(?:pull_request|push|schedule):/.test(stagingSnapshotActivationWorkflowSource),
  "staging snapshot activation workflow must be manually dispatched only"
);
assert(
  /environment:\s*\n\s+name:\s+confluendo-control-staging/.test(
    stagingSnapshotActivationWorkflowSource
  ),
  "staging snapshot activation workflow must use the protected confluendo-control-staging environment"
);
assert(
  /ip18:snapshot-activation-worker/.test(stagingSnapshotActivationWorkflowSource) &&
    /--require-hosted-artifact-store/.test(stagingSnapshotActivationWorkflowSource),
  "staging snapshot activation workflow must run the trusted worker with a hosted artifact store"
);
assert(
  /CONFIRM_CONFLUENDO_SNAPSHOT_ACTIVATION_WORKER:\s*"YES"/.test(
    stagingSnapshotActivationWorkflowSource
  ) &&
    /secrets\.INGESTION_CONTROL_OWNER_DATABASE_URL/.test(stagingSnapshotActivationWorkflowSource) &&
    /secrets\.CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY/.test(
      stagingSnapshotActivationWorkflowSource
    ) &&
    !/FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN|NEXT_PUBLIC_|VAMO_/.test(
      stagingSnapshotActivationWorkflowSource
    ),
  "staging snapshot activation workflow must use only protected activation secrets"
);

assert(
  /\bFSQ_OS_PLACES_PORTAL_ACCESS_TOKEN_ENV\b/.test(fsqAcquisitionSource) &&
    !/TOKEN\s*=\s*['"][^'"]+['"]/.test(fsqAcquisitionSource),
  "FSQ acquisition adapter must reference the Portal token env name only, never embed credential values"
);

assert(
  !/NODE_TLS_REJECT_UNAUTHORIZED/.test(fsqAcquisitionSource),
  "FSQ acquisition adapter must never disable TLS verification"
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
