import { spawnSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";

const testDirectory = join(process.cwd(), "dist", "spec", "test");

if (!existsSync(testDirectory)) {
  console.error(`Compiled test directory does not exist: ${testDirectory}`);
  process.exit(1);
}

const testFiles = readdirSync(testDirectory)
  .filter((file) => file.endsWith(".test.js"))
  .map((file) => join(testDirectory, file));

if (testFiles.length === 0) {
  console.error(`No compiled spec tests found in ${testDirectory}`);
  process.exit(1);
}

const result = spawnSync(process.execPath, ["--test", ...testFiles], {
  stdio: "inherit"
});

process.exit(result.status ?? 1);
