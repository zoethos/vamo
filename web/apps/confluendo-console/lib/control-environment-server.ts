import "server-only";

import { cookies } from "next/headers";
import { CONTROL_ENVIRONMENT_COOKIE, parseControlEnvironment } from "./control-environment";
import {
  getControlEnvironmentConfig,
  getDefaultControlEnvironment,
  type ControlEnvironmentConfig
} from "./control-environment-config";

export async function getActiveControlEnvironmentConfig(): Promise<ControlEnvironmentConfig | null> {
  const cookieStore = await cookies();
  const selected = parseControlEnvironment(cookieStore.get(CONTROL_ENVIRONMENT_COOKIE)?.value);
  const defaultEnvironment = getDefaultControlEnvironment();
  return (
    getControlEnvironmentConfig(selected ?? defaultEnvironment) ??
    getControlEnvironmentConfig(defaultEnvironment)
  );
}
