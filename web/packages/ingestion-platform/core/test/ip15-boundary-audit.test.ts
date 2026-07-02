import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..");
const auditScript = join(packageRoot, "scripts", "ip15-boundary-audit.mjs");
const trapDir = join(packageRoot, "core", "src", "__audit_trap__");

describe("ip15 boundary audit", () => {
  it("passes on the current repository", () => {
    const result = spawnSync(process.execPath, [auditScript], {
      cwd: packageRoot,
      encoding: "utf8"
    });
    assert.equal(
      result.status,
      0,
      `boundary audit failed:\n${result.stdout}\n${result.stderr}`
    );
    assert.match(result.stdout, /Boundary audit passed/);
  });

  it("fails when platform src infers environment from targetId substrings", () => {
    mkdirSync(trapDir, { recursive: true });
    const trapFile = join(trapDir, "env-inference-trap.ts");
    writeFileSync(
      trapFile,
      `export function inferEnv(targetId: string) {
  return targetId.includes("staging") ? "staging" : "production";
}
`
    );
    try {
      const result = spawnSync(process.execPath, [auditScript], {
        cwd: packageRoot,
        encoding: "utf8"
      });
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /must not infer environment from targetId\/targetKey substrings/);
    } finally {
      rmSync(trapDir, { recursive: true, force: true });
    }
  });
});
