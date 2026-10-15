type RoutePhase = "started" | "rerouted" | "handoff" | "completed";
type RouteHealth = "unknown" | "healthy" | "degraded" | "unavailable";

export type AgentMetaEvent = {
  kind: "meta";
  model?: string;
  providerSessionId?: string;
};

export type AgentRoutingEvent = {
  kind: "routing";
  phase: RoutePhase;
  conversationId: string;
  requestId: string;
  attempt: number;
  parentSessionId?: string;
  parentConversationId?: string;
  provider?: string;
  model?: string;
  reason?: string;
  handoffMode?: "native_fork" | "compact_replay";
  retryAfterMs?: number;
  health?: RouteHealth;
  at?: number;
};

export type AgentEvent = AgentMetaEvent | AgentRoutingEvent;
