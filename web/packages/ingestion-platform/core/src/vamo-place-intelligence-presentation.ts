import {
  describeVamoStagingTargetCategoryCompatibility,
  isVamoStagingTargetCategoryCompatible,
  mapVamoSourceCategoryToFeatureType,
  type VamoStagingTargetCategoryCompatibility
} from "./batch-staging-canary-wave-target-compat.js";

export { describeVamoStagingTargetCategoryCompatibility, isVamoStagingTargetCategoryCompatible };
export type { VamoStagingTargetCategoryCompatibility };

export interface VamoPoiTypePresentation {
  operatorLabel: "POI type";
  operatorValue: string;
  technicalMapping: string | null;
}

export function presentVamoPoiType(category: string): VamoPoiTypePresentation {
  const normalized = category.trim().toLowerCase();
  const targetFeatureType = mapVamoSourceCategoryToFeatureType(normalized);

  if (targetFeatureType === "landmark") {
    return {
      operatorLabel: "POI type",
      operatorValue: "Landmark",
      technicalMapping: "feature_type=landmark"
    };
  }

  if (targetFeatureType === "poi") {
    return {
      operatorLabel: "POI type",
      operatorValue: normalized === "poi" ? "General" : titleCase(normalized),
      technicalMapping: "feature_type=poi"
    };
  }

  return {
    operatorLabel: "POI type",
    operatorValue: titleCase(normalized || category),
    technicalMapping: null
  };
}

function titleCase(value: string): string {
  return value
    .split("-")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}
