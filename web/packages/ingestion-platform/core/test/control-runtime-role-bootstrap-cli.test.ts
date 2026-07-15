import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, it } from "node:test";

describe("control runtime-role bootstrap CLI", () => {
  it("rotates only confluendo_app and persists the runtime URL only after verification", () => {
    const source = readFileSync(
      resolve(process.cwd(), "scripts/run-control-runtime-role-bootstrap.mjs"),
      "utf8"
    );

    assert.match(source, /alter role %I login password %L', \$1::text, \$2::text/);
    assert.match(source, /RUNTIME_AUTH_MAX_ATTEMPTS = 6/);
    assert.match(source, /connectRuntimeClientWithRetry\(runtimeDatabaseUrl\)/);
    assert.match(source, /isPasswordAuthenticationFailure/);
    assert.ok(
      source.indexOf("assertRuntimeVerification(verification)") <
        source.indexOf('replaceDotenvValue(profilePath, "INGESTION_CONTROL_DATABASE_URL", runtimeDatabaseUrl)'),
      "the ignored profile must update only after the generated runtime login has been verified"
    );
    assert.match(source, /INGESTION_CONTROL_DATABASE_URL/);
    assert.doesNotMatch(source, /replaceDotenvValue\(profilePath, "INGESTION_CONTROL_OWNER_DATABASE_URL"/);
  });

  it("keeps the PowerShell profile reader clear of the automatic Matches hashtable", () => {
    const source = readFileSync(
      resolve(process.cwd(), "..", "..", "scripts", "Initialize-ConfluendoControlRuntimeRole.ps1"),
      "utf8"
    );

    assert.match(source, /\$profileValues = @\(\)/);
    assert.doesNotMatch(source, /\$matches = @\(\)/i);
  });
});
