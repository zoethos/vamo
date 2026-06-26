import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { parsePipelineSpec, parseTargetProjectSpec } from "../src/index.js";

function fixture(path: string): string {
  return readFileSync(path, "utf8");
}

function paths(result: { errors: Array<{ path: string }> }): string[] {
  return result.errors.map((error) => error.path);
}

describe("ingestion spec kernel", () => {
  it("parses the valid Vamo place-intelligence fixture", () => {
    const pipeline = parsePipelineSpec(
      fixture("fixtures/imported/vamo-place-intelligence/pipeline.yaml")
    );
    const target = parseTargetProjectSpec(
      fixture("fixtures/imported/vamo-place-intelligence/target.yaml")
    );

    assert.equal(pipeline.ok, true);
    assert.equal(target.ok, true);

    if (pipeline.ok) {
      assert.equal(pipeline.value.source.adapter, "fixture");
      assert.equal(pipeline.value.target.adapter, "supabase_postgres");
      assert.equal(pipeline.value.policyRequests.storeMediaBytes, false);
      assert.equal(pipeline.value.normalizedSpecVersion, 1);
    }

    if (target.ok) {
      assert.equal(target.value.engine.exposeServiceRoleToBrowser, false);
      assert.equal(target.value.security.writeMode, "dry_run");
      assert.equal(target.value.normalizedSpecVersion, 1);
    }
  });

  it("returns structured errors for invalid YAML", () => {
    const result = parsePipelineSpec("kind: [");

    assert.equal(result.ok, false);
    assert.equal(result.errors[0]?.code, "invalid_yaml");
    assert.equal(result.errors[0]?.path, "$");
  });

  it("reports missing required source fields with field paths", () => {
    const result = parsePipelineSpec(`
kind: ingestion.pipeline
version: 1
id: missing-source-fields
name: Missing Source Fields
owner: test
source: {}
target:
  id: local
  adapter: postgres
  project: demo
  profile: places
cursor:
  strategy: snapshot
mappings: []
`);

    assert.equal(result.ok, false);
    assert.deepEqual(paths(result).filter((path) => path.startsWith("source.")), [
      "source.adapter",
      "source.license",
      "source.id",
      "source.name"
    ]);
  });

  it("rejects unknown source and target adapter names", () => {
    const pipeline = parsePipelineSpec(`
kind: ingestion.pipeline
version: 1
id: bad-source-adapter
name: Bad Source Adapter
owner: test
source:
  id: local
  name: Local
  adapter: rotating_proxy_scraper
  license:
    name: Local
    attribution: Local
    canStoreFacts: true
    canStoreContent: false
    canStoreMediaBytes: false
target:
  id: local
  adapter: postgres
  project: demo
  profile: places
cursor:
  strategy: snapshot
mappings: []
`);
    const target = parseTargetProjectSpec(`
kind: ingestion.target
version: 1
id: bad-target-adapter
name: Bad Target Adapter
adapter: browser_supabase_client
engine:
  type: postgres
  dsnEnv: DATABASE_URL
security:
  writeMode: dry_run
shipment:
  defaultMode: dry_run
  tables: []
`);

    assert.equal(pipeline.ok, false);
    assert.equal(target.ok, false);
    assert.equal(pipeline.errors.some((error) => error.path === "source.adapter"), true);
    assert.equal(target.errors.some((error) => error.path === "adapter"), true);
  });

  it("rejects snapshot URL and network/evasion controls at spec-parse time", () => {
    const result = parsePipelineSpec(`
kind: ingestion.pipeline
version: 1
id: unsafe-snapshot-source
name: Unsafe Snapshot Source
owner: test
source:
  id: local
  name: Local
  adapter: snapshot
  license:
    name: Local
    attribution: Local
    canStoreFacts: true
    canStoreContent: false
    canStoreMediaBytes: false
  connection:
    snapshotPath: https://example.com/open-dataset.jsonl
    proxy_url: http://127.0.0.1:8888
    ipRotation: true
target:
  id: local
  adapter: postgres
  project: demo
  profile: places
cursor:
  strategy: snapshot
mappings: []
`);

    assert.equal(result.ok, false);
    assert.equal(
      result.errors.some(
        (error) =>
          error.code === "source_connection_violation" &&
          error.path === "source.connection.snapshotPath"
      ),
      true
    );
    assert.equal(
      result.errors.some(
        (error) =>
          error.code === "source_connection_violation" &&
          error.path === "source.connection.proxy_url"
      ),
      true
    );
    assert.equal(
      result.errors.some(
        (error) =>
          error.code === "source_connection_violation" &&
          error.path === "source.connection.ipRotation"
      ),
      true
    );
  });

  it("rejects media-byte storage when source policy does not permit it", () => {
    const result = parsePipelineSpec(`
kind: ingestion.pipeline
version: 1
id: media-policy-contradiction
name: Media Policy Contradiction
owner: test
source:
  id: local
  name: Local
  adapter: fixture
  license:
    name: Local
    attribution: Local
    canStoreFacts: true
    canStoreContent: true
    canStoreMediaBytes: false
target:
  id: local
  adapter: postgres
  project: demo
  profile: places
cursor:
  strategy: snapshot
policyRequests:
  storeFacts: true
  storeContent: true
  storeMediaBytes: true
mappings: []
`);

    assert.equal(result.ok, false);
    assert.equal(
      result.errors.some(
        (error) =>
          error.code === "policy_contradiction" &&
          error.path === "policyRequests.storeMediaBytes"
      ),
      true
    );
  });

  it("parses literal value mappings for derived target fields", () => {
    const result = parsePipelineSpec(`
kind: ingestion.pipeline
version: 1
id: literal-mapping
name: Literal Mapping
owner: test
source:
  id: local
  name: Local
  adapter: fixture
  license:
    name: Local
    attribution: Local
    canStoreFacts: true
    canStoreContent: false
    canStoreMediaBytes: false
target:
  id: local
  adapter: postgres
  project: demo
  profile: places
cursor:
  strategy: snapshot
mappings:
  - value: fsq_os_places
    to: location_canonicals.source_provider
  - from: source.id
    to: location_canonicals.canonical_key
    transform: stable_key
`);

    assert.equal(result.ok, true);
    if (result.ok) {
      assert.deepEqual(result.value.mappings[0], {
        value: "fsq_os_places",
        to: "location_canonicals.source_provider"
      });
      assert.equal(result.value.mappings[1]?.transform, "stable_key");
    }
  });

  it("rejects mappings without a source field or literal value", () => {
    const result = parsePipelineSpec(`
kind: ingestion.pipeline
version: 1
id: bad-mapping
name: Bad Mapping
owner: test
source:
  id: local
  name: Local
  adapter: fixture
  license:
    name: Local
    attribution: Local
    canStoreFacts: true
    canStoreContent: false
    canStoreMediaBytes: false
target:
  id: local
  adapter: postgres
  project: demo
  profile: places
cursor:
  strategy: snapshot
mappings:
  - to: location_canonicals.source_provider
`);

    assert.equal(result.ok, false);
    assert.equal(result.errors.some((error) => error.path === "mappings[0].from"), true);
  });

  it("rejects Supabase service-role exposure to browser/admin code", () => {
    const result = parseTargetProjectSpec(`
kind: ingestion.target
version: 1
id: unsafe-supabase-target
name: Unsafe Supabase Target
adapter: supabase_postgres
engine:
  type: supabase_postgres
  dsnEnv: DATABASE_URL
  serviceRoleSecretEnv: SUPABASE_SERVICE_ROLE
  exposeServiceRoleToBrowser: true
security:
  serverSideOnly: true
  forbidBrowserServiceRole: true
  requireRlsOnExposedSchemas: true
  exposedSchemas:
    - public
  writeMode: dry_run
shipment:
  defaultMode: dry_run
  tables: []
`);

    assert.equal(result.ok, false);
    assert.equal(
      result.errors.some(
        (error) =>
          error.code === "target_security_violation" &&
          error.path === "engine.exposeServiceRoleToBrowser"
      ),
      true
    );
  });

  it("parses Supabase Data API grant requirements with safe defaults", () => {
    const result = parseTargetProjectSpec(`
kind: ingestion.target
version: 1
id: supabase-grants
name: Supabase Grants
adapter: supabase_postgres
engine:
  type: supabase_postgres
  dsnEnv: DATABASE_URL
  exposeServiceRoleToBrowser: false
security:
  serverSideOnly: true
  forbidBrowserServiceRole: true
  requireRlsOnExposedSchemas: true
  requireExplicitDataApiGrants: true
  exposedSchemas:
    - public
  writeMode: dry_run
shipment:
  defaultMode: dry_run
  tables: []
`);

    assert.equal(result.ok, true);
    if (result.ok) {
      assert.equal(result.value.security.requireExplicitDataApiGrants, true);
      assert.deepEqual(result.value.security.dataApiRoles, ["anon", "authenticated"]);
      assert.deepEqual(result.value.security.dataApiPrivileges, ["select"]);
    }
  });

  it("rejects target tables without deterministic upsert keys", () => {
    const result = parseTargetProjectSpec(`
kind: ingestion.target
version: 1
id: missing-keys-target
name: Missing Keys Target
adapter: postgres
engine:
  type: postgres
  dsnEnv: DATABASE_URL
  exposeServiceRoleToBrowser: false
security:
  serverSideOnly: true
  forbidBrowserServiceRole: true
  requireRlsOnExposedSchemas: false
  exposedSchemas: []
  writeMode: dry_run
shipment:
  defaultMode: dry_run
  tables:
    - table: public.generic_places
      mode: upsert
      upsertKeys: []
`);

    assert.equal(result.ok, false);
    assert.equal(
      result.errors.some((error) => error.path === "shipment.tables[0].upsertKeys"),
      true
    );
  });
});
