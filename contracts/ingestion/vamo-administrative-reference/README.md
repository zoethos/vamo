# Vamo Administrative Reference Contract

This consumer-owned contract declares the durable municipality baseline Vamo
expects Confluendo to deliver. It is a schema and provenance contract, not an
authorization to fetch or load a country dataset.

## Required municipality facts

Each source row supplies a stable authority identifier, canonical label, ISO
country code, source parent-administration code, centroid, source dataset
version, source validity dates when supplied, and an attribution carrying the
applicable licence.

The authoritative source id is stored as `location_source_refs.source_place_id`.
The Vamo canonical key is a deterministic derivative, so source identity stays
stable across releases without making source-specific identifiers part of app
code.

## Boundary

1. Vamo commits this bundle.
2. Confluendo imports a pinned snapshot, validates it, and records the Vamo
   commit and content hashes.
3. A release follows the existing artifact, Staging verification, consumer
   inbox, and consumer receipt gates.

The two fixture rows are deliberately bounded validation data. They are not an
Italy release, a claim of complete municipality coverage, a source loader, or
an authorization to acquire a country dataset. The v1 baseline contains only
the core canonical and source-reference records. Aliases and municipality images
are out of scope: aliases require explicit inbox items and their own provenance;
any future visual belongs in the rights-bound visual cache with its own source
and retention policy.
