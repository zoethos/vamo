import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join, relative, sep } from "node:path";

const SOURCE_FILE_PATTERN = /\.(?:[cm]?[jt]sx?)$/;
const NEXT_CONFIG_PATTERN = /^next\.config\.(?:[cm]?js|ts)$/;
const NEXT_IMAGE_IMPORT_PATTERN = /from\s+["']next\/image["']/;
const REMOTE_IMAGE_CONFIGURATION_PATTERN = /\b(?:remotePatterns|domains)\b/;
const LOCAL_BRAND_ASSET_PATTERN = /^\/brand\/[a-z0-9_/-]+\.(?:avif|jpe?g|png|webp)$/i;
const PACKAGE_JSON = "package.json";

function normalizedPath(path) {
  return path.split(sep).join("/");
}

function walkFiles(rootDirectory, predicate, files = []) {
  for (const entry of readdirSync(rootDirectory, { withFileTypes: true })) {
    if ([".next", "dist", "node_modules"].includes(entry.name)) {
      continue;
    }

    const entryPath = join(rootDirectory, entry.name);
    if (entry.isDirectory()) {
      walkFiles(entryPath, predicate, files);
    } else if (predicate(entry.name)) {
      files.push(entryPath);
    }
  }

  return files;
}

function hasDirectSharpDependency(packageJson) {
  return [
    packageJson.dependencies,
    packageJson.devDependencies,
    packageJson.optionalDependencies,
    packageJson.peerDependencies
  ].some((dependencies) => dependencies?.sharp !== undefined);
}

export function findSharpReachabilityViolations({ configFiles, sourceFiles, manifests }) {
  const violations = [];

  for (const file of configFiles) {
    if (REMOTE_IMAGE_CONFIGURATION_PATTERN.test(file.content)) {
      violations.push(`${file.path}: remote Next Image configuration is not allowed while GHSA-f88m-g3jw-g9cj is excepted.`);
    }
  }

  for (const file of sourceFiles) {
    if (!NEXT_IMAGE_IMPORT_PATTERN.test(file.content)) {
      continue;
    }

    if (!file.path.startsWith("web/apps/site/")) {
      violations.push(`${file.path}: only the public site may import next/image while GHSA-f88m-g3jw-g9cj is excepted.`);
      continue;
    }

    const imageElements = [...file.content.matchAll(/<Image\b[\s\S]*?\/>/g)];
    for (const imageElement of imageElements) {
      const sourceMatch = imageElement[0].match(/\bsrc\s*=\s*["']([^"']+)["']/);
      if (!sourceMatch) {
        violations.push(`${file.path}: next/image sources must be fixed local /brand assets while GHSA-f88m-g3jw-g9cj is excepted.`);
      } else if (!LOCAL_BRAND_ASSET_PATTERN.test(sourceMatch[1])) {
        violations.push(`${file.path}: ${sourceMatch[1]} is not an approved local /brand image source while GHSA-f88m-g3jw-g9cj is excepted.`);
      }
    }
  }

  for (const manifest of manifests) {
    if (hasDirectSharpDependency(manifest.packageJson)) {
      violations.push(`${manifest.path}: direct sharp dependencies are not allowed while GHSA-f88m-g3jw-g9cj is excepted.`);
    }
  }

  return violations;
}

export function assertSharpReachabilityIsBounded(inputs) {
  const violations = findSharpReachabilityViolations(inputs);
  if (violations.length > 0) {
    throw new Error(`Sharp reachability guard failed:\n- ${violations.join("\n- ")}`);
  }
}

function loadGuardInputs(repositoryRoot) {
  const webRoot = join(repositoryRoot, "web");
  const files = walkFiles(webRoot, (name) => SOURCE_FILE_PATTERN.test(name) || NEXT_CONFIG_PATTERN.test(name) || name === PACKAGE_JSON);
  const configFiles = [];
  const sourceFiles = [];
  const manifests = [];

  for (const filePath of files) {
    const path = normalizedPath(relative(repositoryRoot, filePath));
    const content = readFileSync(filePath, "utf8");

    if (NEXT_CONFIG_PATTERN.test(filePath.split(sep).at(-1))) {
      configFiles.push({ path, content });
    } else if (filePath.split(sep).at(-1) === PACKAGE_JSON) {
      manifests.push({ path, packageJson: JSON.parse(content) });
    } else if (path.startsWith("web/apps/") && !path.endsWith("/next-env.d.ts")) {
      sourceFiles.push({ path, content });
    }
  }

  return { configFiles, sourceFiles, manifests };
}

function main() {
  const scriptPath = fileURLToPath(import.meta.url);
  const repositoryRoot = join(scriptPath, "..", "..", "..");
  assertSharpReachabilityIsBounded(loadGuardInputs(repositoryRoot));
  console.log("Sharp reachability guard passed: only fixed local Vamo brand assets use Next Image.");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
