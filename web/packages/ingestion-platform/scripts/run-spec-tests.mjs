import { spawnSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";

const requestedSuites = process.argv.slice(2).filter((arg) => !arg.startsWith("-"));
const suites = requestedSuites.length > 0 ? requestedSuites : ["spec", "core"];
const allowedSuites = new Set(["spec", "core"]);

const testFiles = suites.flatMap((suite) => {
  if (!allowedSuites.has(suite)) {
    console.error(`Unknown test suite "${suite}". Expected one of: spec, core.`);
    process.exit(1);
  }

  const testDirectory = join(process.cwd(), "dist", suite, "test");
  if (!existsSync(testDirectory)) {
    console.error(`Compiled test directory does not exist: ${testDirectory}`);
    process.exit(1);
  }

  return readdirSync(testDirectory)
    .filter((file) => file.endsWith(".test.js"))
    .map((file) => join(testDirectory, file));
});

if (testFiles.length === 0) {
  console.error(`No compiled tests found for suites: ${suites.join(", ")}`);
  process.exit(1);
}

const result = spawnSync(process.execPath, ["--test", ...testFiles], {
  stdio: "inherit"
});

process.exit(result.status ?? 1);
