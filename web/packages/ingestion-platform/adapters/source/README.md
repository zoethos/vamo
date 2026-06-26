# Source Adapters

Source adapters read from provider-neutral inputs and emit bounded batches for
the core runner. `fixture` reads local JSONL test fixtures. `snapshot` reads
downloaded local open-dataset JSONL snapshots and rejects URL/proxy/VPN-style
connection controls.

The snapshot adapter's no-network guarantee is structural: it only opens a local
file path after spec validation rejects URL-like `snapshotPath` / `path` values
and network/evasion-intent connection fields such as proxies, VPN settings,
headers, cookies, Tor/SOCKS controls, or IP/user-agent rotation. The denylist is
a fail-loud signal for unsafe intent, not the primary enforcement boundary; no
snapshot connection field is ever used to make a provider call.

Source adapters fetch or read bounded batches from fixture files, snapshots,
APIs, SQL sources, or upload artifacts. They must emit source facts through the
policy engine before durable staging.

Open dataset snapshots must carry source license and attribution metadata in the
pipeline spec. The adapter attaches that attribution to every row so target
mappings can produce attribution-bearing shipment rows without calling a
provider.
