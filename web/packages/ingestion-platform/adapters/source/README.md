# Source Adapters

Source adapters read from provider-neutral inputs and emit bounded batches for
the core runner. The first adapter is `fixture`, which reads local JSONL only and
is used to prove checkpointing, policy evaluation, dead letters, and transform
determinism before any live provider access exists.

Source adapters fetch or read bounded batches from fixture files, snapshots,
APIs, SQL sources, or upload artifacts. They must emit source facts through the
policy engine before durable staging.
