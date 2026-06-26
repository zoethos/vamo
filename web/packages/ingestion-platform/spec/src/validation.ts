import { parse } from "yaml";

import type { SpecValidationError, SpecValidationResult } from "./types.js";

type MutableValidationResult<T> = SpecValidationResult<T> & {
  value?: T;
};

export class ValidationBag {
  readonly errors: SpecValidationError[] = [];

  add(error: SpecValidationError): void {
    this.errors.push(error);
  }

  missing(path: string, description = "Required field is missing."): void {
    this.add({
      code: "missing_required",
      path,
      message: description
    });
  }

  shape(path: string, description: string): void {
    this.add({
      code: "invalid_shape",
      path,
      message: description
    });
  }

  finish<T>(value: T): SpecValidationResult<T> {
    if (this.errors.length > 0) {
      return {
        ok: false,
        errors: this.errors
      };
    }

    return {
      ok: true,
      value,
      errors: []
    };
  }
}

export function parseYamlDocument(input: string | unknown): MutableValidationResult<unknown> {
  if (typeof input !== "string") {
    return {
      ok: true,
      value: input,
      errors: []
    };
  }

  try {
    return {
      ok: true,
      value: parse(input),
      errors: []
    };
  } catch (error) {
    return {
      ok: false,
      errors: [
        {
          code: "invalid_yaml",
          path: "$",
          message: error instanceof Error ? error.message : "YAML could not be parsed."
        }
      ]
    };
  }
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function requireRecord(
  value: unknown,
  path: string,
  errors: ValidationBag
): Record<string, unknown> | undefined {
  if (isRecord(value)) {
    return value;
  }

  if (value === undefined) {
    errors.missing(path);
  } else {
    errors.shape(path, "Expected an object.");
  }

  return undefined;
}

export function requireString(
  record: Record<string, unknown>,
  key: string,
  path: string,
  errors: ValidationBag
): string | undefined {
  const value = record[key];

  if (typeof value === "string" && value.trim().length > 0) {
    return value.trim();
  }

  if (value === undefined) {
    errors.missing(path);
  } else {
    errors.shape(path, "Expected a non-empty string.");
  }

  return undefined;
}

export function optionalString(
  record: Record<string, unknown>,
  key: string,
  path: string,
  errors: ValidationBag
): string | undefined {
  const value = record[key];

  if (value === undefined) {
    return undefined;
  }

  if (typeof value === "string" && value.trim().length > 0) {
    return value.trim();
  }

  errors.shape(path, "Expected a non-empty string.");
  return undefined;
}

export function requireNumber(
  record: Record<string, unknown>,
  key: string,
  path: string,
  errors: ValidationBag
): number | undefined {
  const value = record[key];

  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (value === undefined) {
    errors.missing(path);
  } else {
    errors.shape(path, "Expected a finite number.");
  }

  return undefined;
}

export function requireBoolean(
  record: Record<string, unknown>,
  key: string,
  path: string,
  errors: ValidationBag
): boolean | undefined {
  const value = record[key];

  if (typeof value === "boolean") {
    return value;
  }

  if (value === undefined) {
    errors.missing(path);
  } else {
    errors.shape(path, "Expected a boolean.");
  }

  return undefined;
}

export function optionalBoolean(
  record: Record<string, unknown>,
  key: string,
  path: string,
  errors: ValidationBag,
  fallback: boolean
): boolean {
  const value = record[key];

  if (value === undefined) {
    return fallback;
  }

  if (typeof value === "boolean") {
    return value;
  }

  errors.shape(path, "Expected a boolean.");
  return fallback;
}

export function optionalNumber(
  record: Record<string, unknown>,
  key: string,
  path: string,
  errors: ValidationBag
): number | undefined {
  const value = record[key];

  if (value === undefined) {
    return undefined;
  }

  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  errors.shape(path, "Expected a finite number.");
  return undefined;
}

export function requireArray(
  record: Record<string, unknown>,
  key: string,
  path: string,
  errors: ValidationBag
): unknown[] | undefined {
  const value = record[key];

  if (Array.isArray(value)) {
    return value;
  }

  if (value === undefined) {
    errors.missing(path);
  } else {
    errors.shape(path, "Expected an array.");
  }

  return undefined;
}

export function optionalStringArray(
  record: Record<string, unknown>,
  key: string,
  path: string,
  errors: ValidationBag
): string[] {
  const value = record[key];

  if (value === undefined) {
    return [];
  }

  if (!Array.isArray(value)) {
    errors.shape(path, "Expected an array of strings.");
    return [];
  }

  return value.flatMap((item, index) => {
    if (typeof item === "string" && item.trim().length > 0) {
      return [item.trim()];
    }

    errors.shape(`${path}[${index}]`, "Expected a non-empty string.");
    return [];
  });
}

export function enumValue<T extends readonly string[]>(
  value: string | undefined,
  allowed: T,
  path: string,
  code: SpecValidationError["code"],
  errors: ValidationBag
): T[number] | undefined {
  if (value === undefined) {
    return undefined;
  }

  if ((allowed as readonly string[]).includes(value)) {
    return value as T[number];
  }

  errors.add({
    code,
    path,
    message: `Unknown value "${value}". Allowed values: ${allowed.join(", ")}.`
  });

  return undefined;
}
