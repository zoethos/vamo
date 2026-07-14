import { spawnSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";

const requestedSuites = process.argv.slice(2).filter((arg) => !arg.startsWith("-"));
const suiteDirectories = new Map([
  ["spec", ["dist/spec/test"]],
  ["core", ["dist/core/test"]],
  ["policy", ["dist/policy/test"]],
  ["source", ["dist/adapters/source/test"]],
  ["target", ["dist/adapters/target/test"]],
  ["artifact", ["dist/adapters/artifact/test"]],
  ["adapters", ["dist/adapters/source/test", "dist/adapters/target/test", "dist/adapters/artifact/test"]]
]);
const suites = requestedSuites.length > 0 ? requestedSuites : ["spec", "core", "policy", "source", "target", "artifact"];

const testFiles = suites.flatMap((suite) => {
  const directories = suiteDirectories.get(suite);
  if (!directories) {
    console.error(`Unknown test suite "${suite}". Expected one of: ${[...suiteDirectories.keys()].join(", ")}.`);
    process.exit(1);
  }

  return directories.flatMap((directory) => {
    const testDirectory = join(process.cwd(), directory);
    if (!existsSync(testDirectory)) {
      console.error(`Compiled test directory does not exist: ${testDirectory}`);
      process.exit(1);
    }

    return readdirSync(testDirectory)
      .filter((file) => file.endsWith(".test.js"))
      .map((file) => join(testDirectory, file));
  });
});

if (testFiles.length === 0) {
  console.error(`No compiled tests found for suites: ${suites.join(", ")}`);
  process.exit(1);
}

// Run test files one at a time. Several DB-smoke suites recreate the shared
// disposable `ingestion_platform` schema; the default parallel file runner lets
// them deadlock on the schema lock when INGESTION_TEST_DATABASE_URL is set.
const result = spawnSync(process.execPath, ["--test", "--test-concurrency=1", ...testFiles], {
  stdio: "inherit"
});

process.exit(result.status ?? 1);
