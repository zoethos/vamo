import type { CommandActorType } from "./commands.js";

/** Control-plane batch mutation actors, including policy-bound autonomous agents. */
export type BatchControlActorType = Extract<
  CommandActorType,
  "operator" | "api" | "autonomous_agent"
>;

export interface BatchControlActor {
  type: BatchControlActorType;
  id: string;
}
