/**
 * Vamo staging target category compatibility (pure).
 *
 * The source category is more specific than the current Vamo target feature_type.
 * Restaurant, transport, and hotel are POI subtypes, so they write to Vamo as
 * feature_type=poi while keeping their source category in queue evidence.
 */

export const VAMO_STAGING_NATIVE_TARGET_CATEGORIES = ["poi", "landmark"] as const;
export const VAMO_STAGING_POI_SUBTYPE_CATEGORIES = ["restaurant", "transport", "hotel"] as const;

export type VamoStagingTargetCategoryCompatibilityStatus = "compatible" | "mapped" | "blocked";

export interface VamoStagingTargetCategoryCompatibility {
  status: VamoStagingTargetCategoryCompatibilityStatus;
  label: string;
  detail: string;
  targetFeatureType?: "poi" | "landmark";
}

export function isVamoStagingTargetCategoryCompatible(category: string): boolean {
  return mapVamoSourceCategoryToFeatureType(category) !== null;
}

export function mapVamoSourceCategoryToFeatureType(category: string): "poi" | "landmark" | null {
  const normalized = category.trim().toLowerCase();
  if (normalized === "landmark") {
    return "landmark";
  }
  if (
    normalized === "poi" ||
    (VAMO_STAGING_POI_SUBTYPE_CATEGORIES as readonly string[]).includes(normalized)
  ) {
    return "poi";
  }
  return null;
}

export function describeVamoStagingTargetCategoryCompatibility(
  category: string
): VamoStagingTargetCategoryCompatibility {
  const targetFeatureType = mapVamoSourceCategoryToFeatureType(category);
  if (targetFeatureType === "landmark") {
    return {
      status: "compatible",
      label: "Feature type: Landmark",
      detail: "Writes to Vamo as feature_type=landmark.",
      targetFeatureType
    };
  }
  if (targetFeatureType === "poi") {
    const normalized = category.trim().toLowerCase();
    const isSubtype = normalized !== "poi";
    return {
      status: isSubtype ? "mapped" : "compatible",
      label: isSubtype ? "Maps to POI" : "Feature type: POI",
      detail: isSubtype
        ? `${category} is a POI subtype; writes to Vamo as feature_type=poi.`
        : "Writes to Vamo as feature_type=poi.",
      targetFeatureType
    };
  }
  return {
    status: "blocked",
    label: "Blocked",
    detail: `${category} is not supported for Vamo staging target writes.`
  };
}
