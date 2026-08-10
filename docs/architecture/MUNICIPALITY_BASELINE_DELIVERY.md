# Municipality Baseline Delivery

Status: proposed delivery contract. It is a prerequisite to a real municipality
source release, not an authorization to acquire one.

## Scope

The first baseline contains only core administrative records:

- one `location_canonicals` item per municipality;
- one `location_source_refs` item per municipality;
- authority identifier, name, country, parent code, centroid, dataset version,
  validity facts when supplied, licence, and attribution.

It contains no aliases, photos, or provider-cache payloads. If a later release
writes another product row, that row must be a separately checksummed shipment
item with its own licence and provenance. No trigger or after-apply extension
may create product rows outside the shipment ledger.

## Approval model

At EU scale, an operator cannot meaningfully inspect every municipality row.
An approval therefore means: approve this immutable release hash, this
deterministic partition cohort, its item and target-write envelope, and its
stop limits. It is not an assertion that a human reviewed every record.

The approval record and package key must include the release identifier,
partition ordinal, partition checksum, and source-record count. A receipt then
connects the exact approved cohort to the rows Vamo persisted.

## Deterministic partition contract

For a release, source records are normalized to their stable authority
identifier and sorted by that identifier before partitioning. A partition is
the same ordered set whenever the release content and partition ordinal are the
same. Its checksum is computed over the ordered source identifiers and their
canonical source payload checksums.

The implementation slice must prove all of the following:

1. Reordering source input does not change membership or checksum.
2. The same release and partition ordinal produce the same membership,
   checksum, and package key on repeated runs.
3. A changed source identifier or payload changes the affected partition
   checksum.
4. A package key records the partition ordinal and cannot be reused for a
   different cohort.

## Staging canary shape

`STAGING_CANARY_MAX_ROWS` is currently a hard 50-row limit. This core baseline
writes two target rows per municipality, so a canary sample can contain at most
25 municipalities. The sample must be deterministic and be recorded as a
subset of one partition; it cannot silently stand in for the full partition.

Today the batch model treats a unit's complete content as the material verified
in Staging. It cannot verify a 25-municipality sample and then deliver the
remaining partition. The **partitioned baseline delivery** slice must add that
explicit relationship before any country dataset is commissioned.

## Production envelope

The current production package-wave route derives its maximum target writes
from server-side policy and the operator-approved envelope. The legacy
`PRODUCTION_INBOX_MAX_ROWS = 500` value is not a blanket cap for that batch
route. The future partitioned delivery UI and audit record must display the
effective server-derived envelope; it must not rely on an undocumented number
or count writes that are not shipment items.

## Sequence

1. Promote and verify the municipality schema expansion in Vamo Staging and
   Production using the transactional apply smoke.
2. Implement deterministic partition materialization, canary selection,
   package identity, and receipts in the governed Confluendo-to-Vamo path.
3. Commission one licensed country release only after step 2 is proven.
4. Approve a 25-municipality-or-smaller Staging canary sample, then a
   partition-bounded production package under its displayed envelope.
5. Expand country-by-country from receipts and policy evidence, never by
   bypassing the consumer inbox.
