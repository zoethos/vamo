# FSQ OS Places Snapshot Sample

Small local JSONL sample used to validate the open-dataset snapshot adapter
without provider calls. It mirrors the shape Vamo needs from FSQ Open Source
Places while keeping the repository fixture tiny.

Real ingestion should point `source.connection.snapshotPath` at a downloaded
local FSQ OS Places snapshot and keep the same license/attribution metadata in
the pipeline spec.
