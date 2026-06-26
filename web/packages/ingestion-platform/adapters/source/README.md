# Source Adapters

Source adapters read from provider-neutral inputs and emit bounded batches for
the core runner. `fixture` reads local JSONL test fixtures. `snapshot` reads
downloaded local open-dataset JSONL snapshots and rejects URL/proxy/VPN-style
connection controls.

Source adapters fetch or read bounded batches from fixture files, snapshots,
APIs, SQL sources, or upload artifacts. They must emit source facts through the
policy engine before durable staging.

Open dataset snapshots must carry source license and attribution metadata in the
pipeline spec. The adapter attaches that attribution to every row so target
mappings can produce attribution-bearing shipment rows without calling a
provider.
