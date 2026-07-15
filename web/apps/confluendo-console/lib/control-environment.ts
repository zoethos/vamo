export const CONTROL_ENVIRONMENT_COOKIE = "confluendo_control_environment";

export const CONTROL_ENVIRONMENTS = ["staging", "production"] as const;

export type ControlEnvironment = (typeof CONTROL_ENVIRONMENTS)[number];

export function isControlEnvironment(value: unknown): value is ControlEnvironment {
  return value === "staging" || value === "production";
}

export function parseControlEnvironment(value: unknown): ControlEnvironment | null {
  return isControlEnvironment(value) ? value : null;
}

export function controlEnvironmentLabel(environment: ControlEnvironment): string {
  return environment === "production" ? "Production" : "Staging";
}
