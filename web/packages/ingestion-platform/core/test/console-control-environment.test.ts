import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..");
const webRoot = join(packageRoot, "..", "..");
const consoleRoot = join(webRoot, "apps", "confluendo-console");

const environmentRoute = readFileSync(
  join(consoleRoot, "app", "api", "admin", "control-environment", "route.ts"),
  "utf8"
);
const environmentConfig = readFileSync(join(consoleRoot, "lib", "control-environment-config.ts"), "utf8");
const shell = readFileSync(
  join(consoleRoot, "app", "admin", "ingestion", "ingestion-console-shell.tsx"),
  "utf8"
);
const providerPage = readFileSync(join(consoleRoot, "app", "admin", "providers", "page.tsx"), "utf8");
const productionRoutes = [
  "production-inbox/route.ts",
  "production-package-wave/approve/route.ts",
  "production-package-wave/apply/route.ts",
  "production-package-wave/apply/preflight/route.ts",
  "production-package-wave/apply-wave/route.ts",
  "production-package-wave/apply-wave/preflight/route.ts"
].map((relativePath) =>
  readFileSync(join(consoleRoot, "app", "api", "admin", "ingestion", relativePath), "utf8")
);

describe("console control environment boundaries", () => {
  it("uses a server-owned, same-origin workspace selector", () => {
    assert.match(environmentRoute, /requireSameOriginJsonMutation/);
    assert.match(environmentRoute, /httpOnly:\s*true/);
    assert.match(environmentRoute, /sameSite:\s*"lax"/);
    assert.match(environmentRoute, /getControlEnvironmentConfig\(environment\)/);
    assert.doesNotMatch(environmentRoute, /databaseUrl|connectionString/i);
  });

  it("requires complete prefixed profiles and keeps legacy fallback production-only", () => {
    assert.match(environmentConfig, /CONFLUENDO_CONTROL_\$\{controlEnvironment\.toUpperCase\(\)\}/);
    assert.match(environmentConfig, /if \(controlEnvironment !== "production"\)/);
    assert.match(environmentConfig, /NEXT_PUBLIC_SUPABASE_URL/);
    assert.match(environmentConfig, /INGESTION_CONTROL_DATABASE_URL/);
  });

  it("does not render production handoff controls in a staging workspace", () => {
    assert.match(shell, /const productionWorkspace = controlEnvironment === "production"/);
    assert.match(shell, /<ProductionWorkspaceRequired action="approve a production package wave"/);
    assert.match(shell, /<ProductionWorkspaceRequired action="request a production-inbox handoff"/);
    assert.match(providerPage, /<ControlEnvironmentSwitcher/);
  });

  it("rejects production inbox and apply routes outside the production workspace", () => {
    for (const routeSource of productionRoutes) {
      assert.match(routeSource, /environmentConfig\??\.environment !== "production"/);
      assert.match(routeSource, /getActiveControlEnvironmentConfig/);
      assert.doesNotMatch(routeSource, /process\.env\.VAMO_PRODUCTION_INBOX/);
    }
  });
});
