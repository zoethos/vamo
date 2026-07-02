/**
 * Canonical target keys and known legacy aliases.
 *
 * IP-15.2: environment is never encoded in the target key. Historical ledger
 * rows may still reference legacy alias keys; read paths resolve canonical and
 * alias keys equivalently without rewriting audit history.
 */

/** Canonical consumer target key for Vamo place intelligence. */
export const VAMO_PLACE_INTELLIGENCE_TARGET_KEY = "vamo-place-intelligence";

/**
 * Canonical target key -> legacy alias keys that may still appear in historical
 * shipment/package ledger rows. Do not emit new rows with alias keys.
 */
export const LEGACY_TARGET_ALIASES: Readonly<Record<string, readonly string[]>> = {
  [VAMO_PLACE_INTELLIGENCE_TARGET_KEY]: ["vamo-place-intelligence-staging"]
};

/**
 * Returns the canonical key and every legacy alias that should match ledger
 * lookups for a proposal target key (canonical or legacy).
 */
export function equivalentTargetKeys(targetKey: string): string[] {
  const aliases = LEGACY_TARGET_ALIASES[targetKey];
  if (aliases) {
    return [targetKey, ...aliases];
  }
  for (const [canonical, legacyAliases] of Object.entries(LEGACY_TARGET_ALIASES)) {
    if (legacyAliases.includes(targetKey)) {
      return [canonical, ...legacyAliases];
    }
  }
  return [targetKey];
}

export function isLegacyTargetKey(targetKey: string): boolean {
  return Object.values(LEGACY_TARGET_ALIASES).some((aliases) => aliases.includes(targetKey));
}

/**
 * Looks up a value in a map keyed by shipment target_key, trying the proposal
 * key and any equivalent legacy/canonical aliases.
 */
export function lookupByTargetIdentity<T>(map: Map<string, T>, proposalTargetKey: string): T | null {
  for (const key of equivalentTargetKeys(proposalTargetKey)) {
    const hit = map.get(key);
    if (hit) {
      return hit;
    }
  }
  return null;
}
