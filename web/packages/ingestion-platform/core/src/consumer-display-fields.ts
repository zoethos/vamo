import type {
  ConsumerDisplayFieldPresenter,
  ConsumerDisplayFieldSpec
} from "../../spec/src/types.js";
import { presentVamoPoiType } from "./vamo-place-intelligence-presentation.js";

export type { ConsumerDisplayFieldPresenter, ConsumerDisplayFieldSpec };

export interface ConsumerDisplayResolutionContext {
  scope: {
    category?: string;
    geography?: string;
    country?: string;
  };
  target: {
    key: string;
    environment: string;
  };
  source: {
    key: string;
  };
}

export interface ResolvedConsumerDisplayField {
  key: string;
  label: string;
  value: string;
  detail?: string;
}

export const VAMO_PLACE_INTELLIGENCE_QUEUE_DISPLAY_FIELDS: readonly ConsumerDisplayFieldSpec[] = [
  {
    key: "poi_type",
    label: "POI type",
    source: "scope.category",
    presenter: "vamo_poi_type",
    detail: {
      source: "scope.category",
      presenter: "vamo_feature_type_mapping"
    }
  }
];

export function resolveConsumerDisplayFields(
  fields: readonly ConsumerDisplayFieldSpec[] | undefined,
  context: ConsumerDisplayResolutionContext
): ResolvedConsumerDisplayField[] {
  return (fields ?? []).map((field) => {
    const rawValue = resolveDisplaySource(field.source, context);
    const detailRawValue = field.detail
      ? resolveDisplaySource(field.detail.source, context)
      : undefined;
    const detail = field.detail
      ? presentDisplayValue(detailRawValue, field.detail.presenter)
      : undefined;

    return {
      key: field.key,
      label: field.label,
      value: presentDisplayValue(rawValue, field.presenter),
      detail: detail && detail !== "—" ? detail : undefined
    };
  });
}

export function resolveDefaultBatchQueueDisplayFields(input: {
  projectKey: string;
  targetKey: string;
}): readonly ConsumerDisplayFieldSpec[] {
  if (input.projectKey === "vamo" && input.targetKey === "vamo-place-intelligence") {
    return VAMO_PLACE_INTELLIGENCE_QUEUE_DISPLAY_FIELDS;
  }
  return [];
}

function resolveDisplaySource(
  source: string,
  context: ConsumerDisplayResolutionContext
): string | undefined {
  switch (source) {
    case "scope.category":
      return context.scope.category;
    case "scope.geography":
      return context.scope.geography;
    case "scope.country":
      return context.scope.country;
    case "source.key":
      return context.source.key;
    case "target.key":
      return context.target.key;
    case "target.environment":
      return context.target.environment;
    default:
      return undefined;
  }
}

function presentDisplayValue(
  value: string | undefined,
  presenter: ConsumerDisplayFieldPresenter | undefined
): string {
  if (!value) {
    return "—";
  }

  switch (presenter ?? "raw") {
    case "title_case":
      return titleCase(value);
    case "vamo_poi_type":
      return presentVamoPoiType(value).operatorValue;
    case "vamo_feature_type_mapping":
      return presentVamoPoiType(value).technicalMapping ?? "No consumer mapping";
    case "raw":
      return value;
  }
}

function titleCase(value: string): string {
  return value
    .split("-")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}
