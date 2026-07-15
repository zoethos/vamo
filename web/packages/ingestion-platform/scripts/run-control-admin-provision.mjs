#!/usr/bin/env node

// Trusted bootstrap command for the current Vamo-only console authorization
// model. It is intentionally not a browser or hosted-console capability.

import { Client } from "pg";

import { provisionVamoControlAdmin } from "../dist/core/src/control-admin-provisioning.js";

const SUPABASE_URL_ENV = "CONFLUENDO_CONTROL_ADMIN_PROVISION_SUPABASE_URL";
const SUPABASE_SECRET_KEY_ENV = "CONFLUENDO_CONTROL_ADMIN_PROVISION_SUPABASE_SECRET_KEY";
const CONTROL_DATABASE_ENV = "CONFLUENDO_CONTROL_ADMIN_PROVISION_DATABASE_URL";
const EXECUTE_CONFIRMATION_ENV = "CONFIRM_CONFLUENDO_CONTROL_ADMIN_PROVISION";
const PRODUCTION_CONFIRMATION_ENV = "CONFLUENDO_CONTROL_ADMIN_PROVISION_CONFIRM_PRODUCTION";
const USERS_PER_PAGE = 1_000;
const MAX_USER_PAGES = 100;

const args = parseArgs(process.argv.slice(2));

if (!args.email || !args.auditReason || !args.controlEnvironment) {
  printUsage();
  process.exit(1);
}

if (args.controlEnvironment !== "staging" && args.controlEnvironment !== "production") {
  fail("--control-environment must be staging or production.");
}

if (!args.execute) {
  console.log("Confluendo Vamo console-admin provisioning preview");
  console.log(`- control environment: ${args.controlEnvironment}`);
  console.log("- project: vamo");
  console.log("- role: admin (MFA required)");
  console.log(`- requested email: ${normalizeEmail(args.email)}`);
  console.log("- Auth and control-plane writes: none");
  console.log(
    "Execute requires --execute, CONFIRM_CONFLUENDO_CONTROL_ADMIN_PROVISION=YES, a Supabase Secret key, and an owner control-DB URL."
  );
  process.exit(0);
}

if (process.env[EXECUTE_CONFIRMATION_ENV] !== "YES") {
  fail(`${EXECUTE_CONFIRMATION_ENV}=YES is required for provisioning.`);
}
if (
  args.controlEnvironment === "production" &&
  process.env[PRODUCTION_CONFIRMATION_ENV] !== "PRODUCTION"
) {
  fail(`${PRODUCTION_CONFIRMATION_ENV}=PRODUCTION is required for production provisioning.`);
}

const supabaseUrl = requireHttpsUrl(process.env[SUPABASE_URL_ENV], SUPABASE_URL_ENV);
const supabaseSecretKey = requireValue(process.env[SUPABASE_SECRET_KEY_ENV], SUPABASE_SECRET_KEY_ENV);
const controlDatabaseUrl = requireValue(process.env[CONTROL_DATABASE_ENV], CONTROL_DATABASE_ENV);

const client = new Client({ connectionString: controlDatabaseUrl });
try {
  await client.connect();
  const result = await provisionVamoControlAdmin({
    authGateway: new SupabaseAuthAdminGateway({ url: supabaseUrl, secretKey: supabaseSecretKey }),
    client,
    email: args.email,
    auditReason: args.auditReason,
    controlEnvironment: args.controlEnvironment
  });

  console.log("Vamo console administrator provisioned");
  console.log(`- control environment: ${args.controlEnvironment}`);
  console.log(`- email: ${result.email}`);
  console.log(`- Supabase Auth identity: ${result.authIdentity}`);
  console.log(`- Vamo admin grant: ${result.grant}`);
  console.log("- MFA is required before the administrator can use protected console controls.");
} catch (error) {
  console.error(`Control-admin provisioning failed: ${safeErrorMessage(error)}`);
  process.exitCode = 1;
} finally {
  await client.end().catch(() => undefined);
}

class SupabaseAuthAdminGateway {
  constructor({ url, secretKey }) {
    this.url = url;
    this.secretKey = secretKey;
  }

  async findUserByEmail(email) {
    const expectedEmail = normalizeEmail(email);
    for (let page = 1; page <= MAX_USER_PAGES; page += 1) {
      const payload = await this.request(
        `/auth/v1/admin/users?page=${page}&per_page=${USERS_PER_PAGE}`,
        { method: "GET" }
      );
      const users = readUsers(payload);
      const matched = users.find((user) => normalizeEmail(user.email) === expectedEmail);
      if (matched) {
        return toAuthUser(matched);
      }
      if (users.length < USERS_PER_PAGE) {
        return null;
      }
    }
    throw new Error("Supabase Auth user lookup exceeded the configured pagination limit.");
  }

  async createConfirmedEmailUser(email) {
    try {
      const payload = await this.request("/auth/v1/admin/users", {
        method: "POST",
        body: JSON.stringify({ email, email_confirm: true })
      });
      return toAuthUser(payload);
    } catch (error) {
      const concurrentUser = await this.findUserByEmail(email);
      if (concurrentUser) {
        return concurrentUser;
      }
      throw error;
    }
  }

  async deleteUser(userId) {
    await this.request(`/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
      method: "DELETE"
    });
  }

  async request(path, init) {
    const response = await fetch(new URL(path, this.url), {
      ...init,
      headers: {
        apikey: this.secretKey,
        authorization: `Bearer ${this.secretKey}`,
        ...(init.body ? { "content-type": "application/json" } : {})
      }
    });
    if (!response.ok) {
      throw new Error(`Supabase Auth admin request failed with status ${response.status}.`);
    }
    if (response.status === 204) {
      return {};
    }
    return response.json();
  }
}

function parseArgs(values) {
  const parsed = { execute: false };
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--execute") {
      parsed.execute = true;
      continue;
    }
    if (value === "--email") {
      parsed.email = values[++index];
      continue;
    }
    if (value === "--audit-reason") {
      parsed.auditReason = values[++index];
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

function readUsers(payload) {
  if (Array.isArray(payload)) return payload;
  if (payload && typeof payload === "object" && Array.isArray(payload.users)) return payload.users;
  throw new Error("Supabase Auth user lookup returned an invalid response.");
}

function toAuthUser(value) {
  if (!value || typeof value !== "object") {
    throw new Error("Supabase Auth returned an invalid user response.");
  }
  const id = typeof value.id === "string" ? value.id.trim() : "";
  const email = typeof value.email === "string" ? value.email.trim() : "";
  const emailConfirmedAt =
    typeof value.email_confirmed_at === "string"
      ? value.email_confirmed_at
      : typeof value.confirmed_at === "string"
        ? value.confirmed_at
        : null;
  if (!id || !email) {
    throw new Error("Supabase Auth returned an incomplete user response.");
  }
  return { id, email, emailConfirmedAt };
}

function requireValue(value, name) {
  const normalized = value?.trim();
  if (!normalized) {
    fail(`${name} is required in the trusted provisioning environment.`);
  }
  return normalized;
}

function requireHttpsUrl(value, name) {
  const normalized = requireValue(value, name);
  try {
    const url = new URL(normalized);
    if (url.protocol !== "https:") {
      fail(`${name} must use https.`);
    }
    return url.toString();
  } catch {
    fail(`${name} must be a valid https URL.`);
  }
}

function normalizeEmail(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function safeErrorMessage(error) {
  if (!(error instanceof Error)) {
    return "Unknown provisioning error.";
  }
  return error.message.replace(/(?:sb_secret_|eyJ[a-zA-Z0-9_-]{10,})\S*/g, "[redacted]");
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function printUsage() {
  console.error(
    "Usage: control:provision-vamo-admin -- --email <email> --audit-reason <reason> --control-environment staging|production [--execute]"
  );
}
