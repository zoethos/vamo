import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { getSupabasePublicConfig } from "./supabase-config";

let cached: SupabaseClient | null = null;

export function getSupabaseAnonClient(): SupabaseClient | null {
  const config = getSupabasePublicConfig();
  if (!config) return null;
  if (!cached) {
    cached = createClient(config.url, config.anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }
  return cached;
}
