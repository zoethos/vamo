#!/usr/bin/env node

// Trusted local bootstrap only. This script creates no database objects; it
// rotates the existing least-privilege runtime login and updates an ignored
// local profile only after that login is verified.

import { randomBytes } from "node:crypto";
import { readFile, rename, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import { Client } from "pg";

import {
  assertConfluendoControlRuntimeDatabaseUrl,
  deriveConfluendoControlRuntimeDatabaseUrl
} from "../dist/core/src/control-runtime-database-role.js";

const OWNER_DATABASE_URL_ENV = "CONFLUENDO_CONTROL_RUNTIME_BOOTSTRAP_OWNER_DATABASE_URL";
const PROFILE_PATH_ENV = "CONFLUENDO_CONTROL_RUNTIME_BOOTSTRAP_PROFILE_PATH";
const EXECUTE_CONFIRMATION_ENV = "CONFIRM_CONFLUENDO_CONTROL_RUNTIME_BOOTSTRAP";
const PRODUCTION_CONFIRMATION_ENV = "CONFLUENDO_CONTROL_RUNTIME_BOOTSTRAP_CONFIRM_PRODUCTION";
const RUNTIME_ROLE_NAME = "confluendo_app";

const args = parseArgs(process.argv.slice(2));
if (args.controlEnvironment !== "staging" && args.controlEnvironment !== "production") {
  printUsage();
  process.exit(1);
}

if (!args.execute) {
  console.log("Confluendo control runtime-role bootstrap preview");
  console.log(`- control environment: ${args.controlEnvironment}`);
  console.log(`- runtime role: ${RUNTIME_ROLE_NAME}`);
  console.log("- updates only the ignored local INGESTION_CONTROL_DATABASE_URL profile entry after verification");
  console.log("- database, profile, and credential writes: none");
  console.log(
    "Execute requires --execute, CONFIRM_CONFLUENDO_CONTROL_RUNTIME_BOOTSTRAP=YES, and an owner session-pooler connection URL."
  );
  process.exit(0);
}

if (process.env[EXECUTE_CONFIRMATION_ENV] !== "YES") {
  fail(`${EXECUTE_CONFIRMATION_ENV}=YES is required.`);
}
if (
  args.controlEnvironment === "production" &&
  process.env[PRODUCTION_CONFIRMATION_ENV] !== "PRODUCTION"
) {
  fail(`${PRODUCTION_CONFIRMATION_ENV}=PRODUCTION is required for production.`);
}

const ownerDatabaseUrl = requireValue(process.env[OWNER_DATABASE_URL_ENV], OWNER_DATABASE_URL_ENV);
const profilePath = requireValue(process.env[PROFILE_PATH_ENV], PROFILE_PATH_ENV);
const generatedPassword = randomBytes(48).toString("base64url");
const runtimeDatabaseUrl = deriveConfluendoControlRuntimeDatabaseUrl(ownerDatabaseUrl, generatedPassword);
assertConfluendoControlRuntimeDatabaseUrl(runtimeDatabaseUrl);

const ownerClient = new Client({ connectionString: ownerDatabaseUrl });
const runtimeClient = new Client({ connectionString: runtimeDatabaseUrl });

try {
  await ownerClient.connect();
  const role = await loadRuntimeRole(ownerClient);
  assertRuntimeRoleIsSafe(role);
  await rotateRuntimeRolePassword(ownerClient, generatedPassword);

  await runtimeClient.connect();
  const verification = await verifyRuntimeRole(runtimeClient);
  assertRuntimeVerification(verification);
  await replaceDotenvValue(profilePath, "INGESTION_CONTROL_DATABASE_URL", runtimeDatabaseUrl);

  console.log("Confluendo control runtime role configured");
  console.log(`- control environment: ${args.controlEnvironment}`);
  console.log(`- runtime role: ${RUNTIME_ROLE_NAME}`);
  console.log("- runtime profile entry: INGESTION_CONTROL_DATABASE_URL updated after verification");
  console.log("- owner profile entry: unchanged");
  console.log("- verification: least-privilege control access confirmed");
} catch (error) {
  console.error(`Control runtime-role bootstrap failed: ${safeErrorMessage(error)}`);
  process.exitCode = 1;
} finally {
  await runtimeClient.end().catch(() => undefined);
  await ownerClient.end().catch(() => undefined);
}

function parseArgs(values) {
  const parsed = { execute: false, controlEnvironment: undefined };
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--execute") {
      parsed.execute = true;
      continue;
    }
    if (value === "--control-environment") {
      parsed.controlEnvironment = values[++index];
      continue;
    }
    fail(`Unknown argument: ${value}`);
  }
  return parsed;
}

async function loadRuntimeRole(client) {
  const result = await client.query(
    `select rolname, rolcanlogin, rolsuper, rolcreaterole, rolcreatedb, rolbypassrls
       from pg_roles
      where rolname = $1`,
    [RUNTIME_ROLE_NAME]
  );
  if (result.rowCount !== 1) {
    throw new Error(`Required runtime role ${RUNTIME_ROLE_NAME} does not exist. Apply the control bootstrap first.`);
  }
  return result.rows[0];
}

function assertRuntimeRoleIsSafe(role) {
  if (!role.rolcanlogin) {
    throw new Error(`Runtime role ${RUNTIME_ROLE_NAME} must have LOGIN enabled.`);
  }
  if (role.rolsuper || role.rolcreaterole || role.rolcreatedb || role.rolbypassrls) {
    throw new Error(`Runtime role ${RUNTIME_ROLE_NAME} has unsafe elevated PostgreSQL attributes.`);
  }
}

async function rotateRuntimeRolePassword(client, password) {
  const statement = await client.query(
    "select format('alter role %I login password %L', $1, $2) as sql",
    [RUNTIME_ROLE_NAME, password]
  );
  await client.query(statement.rows[0].sql);
}

async function verifyRuntimeRole(client) {
  const result = await client.query(`
    select
      current_user as current_user,
      has_schema_privilege(current_user, 'ingestion_platform', 'USAGE') as has_schema_usage,
      has_table_privilege(current_user, 'ingestion_platform.ingestion_targets', 'SELECT') as can_read_targets,
      has_table_privilege(current_user, 'ingestion_platform.ingestion_snapshot_commission_requests', 'UPDATE') as can_update_commission_requests
  `);
  return result.rows[0];
}

function assertRuntimeVerification(verification) {
  if (
    verification.current_user !== RUNTIME_ROLE_NAME ||
    !verification.has_schema_usage ||
    !verification.can_read_targets ||
    verification.can_update_commission_requests
  ) {
    throw new Error("Runtime credential verification did not confirm the expected least-privilege control access.");
  }
}

async function replaceDotenvValue(profilePath, name, value) {
  const resolvedPath = resolve(profilePath);
  const content = await readFile(resolvedPath, "utf8");
  const newline = content.includes("\r\n") ? "\r\n" : "\n";
  const pattern = new RegExp(`^(?:export\\s+)?${escapeRegExp(name)}\\s*=`, "i");
  const lines = content.split(/\r?\n/);
  const matchingIndexes = lines.flatMap((line, index) => (pattern.test(line.trim()) ? [index] : []));
  if (matchingIndexes.length > 1) {
    throw new Error(`Profile contains duplicate ${name} entries.`);
  }
  const entry = `${name}=${value}`;
  if (matchingIndexes.length === 1) {
    lines[matchingIndexes[0]] = entry;
  } else {
    if (lines.at(-1) === "") lines.pop();
    lines.push(entry);
  }

  const temporaryPath = `${resolvedPath}.runtime-role.tmp`;
  await writeFile(temporaryPath, `${lines.join(newline)}${newline}`, { encoding: "utf8", mode: 0o600 });
  await rename(temporaryPath, resolvedPath);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function requireValue(value, name) {
  const normalized = value?.trim();
  if (!normalized) {
    fail(`${name} is required in the trusted bootstrap environment.`);
  }
  return normalized;
}

function safeErrorMessage(error) {
  if (!(error instanceof Error)) return "Unknown runtime-role bootstrap error.";
  return error.message.replace(/postgres(?:ql)?:\/\/[^\s]+/gi, "[redacted]");
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function printUsage() {
  console.error(
    "Usage: control:bootstrap-runtime-role -- --control-environment staging|production [--execute]"
  );
}
