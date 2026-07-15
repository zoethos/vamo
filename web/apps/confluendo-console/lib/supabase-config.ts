import { getControlEnvironmentConfig } from "./control-environment-config";
import { getActiveControlEnvironmentConfig } from "./control-environment-server";
import type { ControlEnvironment } from "./control-environment";

export type SupabasePublicConfig = {
  url: string;
  publishableKey: string;
};

export async function getSupabasePublicConfig(): Promise<SupabasePublicConfig | null> {
  const config = await getActiveControlEnvironmentConfig();
  if (!config) {
    return null;
  }

  return { url: config.supabaseUrl, publishableKey: config.supabasePublishableKey };
}

export function getSupabasePublicConfigForEnvironment(
  environment: ControlEnvironment
): SupabasePublicConfig | null {
  const config = getControlEnvironmentConfig(environment);
  return config ? { url: config.supabaseUrl, publishableKey: config.supabasePublishableKey } : null;
}
