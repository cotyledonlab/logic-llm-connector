import { randomUUID } from "node:crypto";

import { McpServer } from "@modelcontextprotocol/server";
import { z } from "zod";

export const BRIDGE_PROTOCOL_VERSION = "1.0.0" as const;

export type Reliability =
  | "verified_deterministic"
  | "verified_ui_driven"
  | "best_effort"
  | "unsupported";

export interface Evidence {
  source: string;
  observedAt: string;
  value: unknown;
}

export interface DoctorCheck {
  id: string;
  status: "passed" | "warning" | "failed" | "unknown";
  summary: string;
  remediation?: string;
  evidence: Evidence[];
}

export interface DoctorResult {
  protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
  operationId: string;
  status: "succeeded" | "partial" | "failed" | "cancelled" | "timed_out";
  reliability: Reliability;
  startedAt: string;
  finishedAt: string;
  data: { checks: DoctorCheck[] };
  evidence: Evidence[];
}

export interface AXNodeSnapshot {
  id: string;
  parentId: string | null;
  role: string;
  subrole: string | null;
  identifier: string | null;
  enabled: boolean | null;
  focused: boolean | null;
  childCount: number;
}

export interface AXInspectionResult {
  protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
  operationId: string;
  status: "succeeded" | "partial" | "failed" | "cancelled" | "timed_out";
  reliability: Reliability;
  startedAt: string;
  finishedAt: string;
  data: {
    application: { bundleIdentifier: "com.apple.logic10"; pid: number };
    capturedAt: string;
    limits: { maxDepth: number; maxNodes: number };
    truncated: boolean;
    nodes: AXNodeSnapshot[];
  };
  evidence: Evidence[];
}

export interface TransportState {
  playing: "playing" | "stopped" | "unknown";
  cycle: "enabled" | "disabled" | "unknown";
  recordReady: "ready" | "not_ready" | "unknown";
  observedAt: string | null;
}

export interface TransportStateResult {
  protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
  operationId: string;
  status: "succeeded" | "partial" | "failed" | "cancelled" | "timed_out";
  reliability: Reliability;
  startedAt: string;
  finishedAt: string;
  data: TransportState;
  evidence: Evidence[];
}

export interface TransportOperationResult extends Omit<TransportStateResult, "data"> {
  data: {
    requestedState: "playing" | "stopped";
    commandDispatched: boolean;
    state: TransportState;
  };
}

export interface TransportPosition {
  display: string | null;
  observedAt: string | null;
}

export interface TransportLocationOperationResult extends Omit<TransportStateResult, "data"> {
  data: {
    requestedDirection: "backward" | "forward";
    steps: number;
    commandDispatched: boolean;
    initialPosition: TransportPosition;
    position: TransportPosition;
  };
}

export interface TransportLocateOperationResult extends Omit<TransportStateResult, "data"> {
  data: {
    requestedTarget: "project_start";
    commandDispatched: boolean;
    initialPosition: TransportPosition;
    position: TransportPosition;
  };
}

export interface ProjectIdentity {
  name: string;
  path: string;
  modified: boolean;
  observedAt: string;
}

export type ProjectLifecycleAction = "observe" | "open" | "save" | "close" | "reopen" | "cleanup";
export type ProjectLifecycleFailure =
  | "fixture_not_found"
  | "invalid_fixture"
  | "user_project_open"
  | "no_managed_project"
  | "project_identity_changed"
  | "unsaved_changes"
  | "dialog_presented"
  | "automation_denied"
  | "command_failed"
  | "postcondition_failed"
  | "cleanup_failed";

export interface ProjectLifecycleResult extends Omit<TransportStateResult, "data"> {
  data: {
    action: ProjectLifecycleAction;
    commandDispatched: boolean;
    project?: ProjectIdentity;
    managedProjectPath?: string;
    policyContext: boolean;
    cleanupPerformed: boolean;
    failure?: ProjectLifecycleFailure;
  };
}

export type LogicTrackType = "software_instrument" | "audio" | "external_midi" | "unknown";
export type TrackOperationAction =
  | "observe" | "create" | "rename" | "select" | "duplicate" | "reorder" | "delete";
export type TrackOperationFailure =
  | "project_policy_missing" | "test_mode_inactive" | "accessibility_unavailable"
  | "logic_not_running" | "logic_not_focused" | "track_not_found"
  | "unsupported_track_type" | "invalid_name" | "invalid_position"
  | "confirmation_required" | "dialog_presented" | "command_failed"
  | "postcondition_failed" | "undo_unavailable";

export interface LogicTrackIdentity {
  id: string;
  position: number;
  type: LogicTrackType;
  name: string;
  selected: boolean;
  observedAt: string;
}

export interface TrackOperationResult extends Omit<TransportStateResult, "data"> {
  data: {
    action: TrackOperationAction;
    commandDispatched: boolean;
    policyContext: boolean;
    targetTrackId?: string;
    undoAvailable: boolean;
    tracks: LogicTrackIdentity[];
    failure?: TrackOperationFailure;
  };
}

export interface LogicBridge {
  doctor(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
    operationId: string;
  }): Promise<DoctorResult>;
  inspectUI(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
    operationId: string;
    maxDepth: number;
    maxNodes: number;
  }): Promise<AXInspectionResult>;
  transportState(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
    operationId: string;
  }): Promise<TransportStateResult>;
  setTransportPlaying(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
    operationId: string;
    playing: boolean;
    timeoutMs: number;
  }): Promise<TransportOperationResult>;
  moveTransportPlayhead(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
    operationId: string;
    direction: "backward" | "forward";
    steps: number;
    timeoutMs: number;
  }): Promise<TransportLocationOperationResult>;
  locateTransport(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
    operationId: string;
    target: "project_start";
    timeoutMs: number;
  }): Promise<TransportLocateOperationResult>;
  projectState(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
    operationId: string;
  }): Promise<ProjectLifecycleResult>;
  openTestProject(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
    operationId: string;
    fixturePath: string;
    timeoutMs: number;
  }): Promise<ProjectLifecycleResult>;
  saveTestProject(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
    operationId: string;
    timeoutMs: number;
  }): Promise<ProjectLifecycleResult>;
  closeTestProject(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
    operationId: string;
    timeoutMs: number;
  }): Promise<ProjectLifecycleResult>;
  reopenTestProject(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
    operationId: string;
    timeoutMs: number;
  }): Promise<ProjectLifecycleResult>;
  cleanupTestProject(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
    operationId: string;
    timeoutMs: number;
  }): Promise<ProjectLifecycleResult>;
  trackState(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
    operationId: string;
  }): Promise<TrackOperationResult>;
  createTrack(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION; operationId: string;
    type: Exclude<LogicTrackType, "unknown">; name?: string; timeoutMs: number;
  }): Promise<TrackOperationResult>;
  renameTrack(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION; operationId: string;
    trackId: string; name: string; timeoutMs: number;
  }): Promise<TrackOperationResult>;
  selectTrack(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION; operationId: string;
    trackId: string; timeoutMs: number;
  }): Promise<TrackOperationResult>;
  duplicateTrack(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION; operationId: string;
    trackId: string; name?: string; timeoutMs: number;
  }): Promise<TrackOperationResult>;
  reorderTrack(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION; operationId: string;
    trackId: string; position: number; timeoutMs: number;
  }): Promise<TrackOperationResult>;
  deleteTrack(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION; operationId: string;
    trackId: string; confirm: boolean; timeoutMs: number;
  }): Promise<TrackOperationResult>;
}

export interface LogicMcpServerDependencies {
  bridge: LogicBridge;
  createOperationId?: () => string;
  diagnosticsEnabled?: boolean;
}

const evidenceSchema = z.object({
  source: z.string(),
  observedAt: z.iso.datetime(),
  value: z.unknown(),
});

const checkSchema = z.object({
  id: z.string(),
  status: z.enum(["passed", "warning", "failed", "unknown"]),
  summary: z.string(),
  remediation: z.string().optional(),
  evidence: z.array(evidenceSchema),
});

const outputSchema = z.object({
  operationId: z.string(),
  status: z.enum(["succeeded", "partial", "failed", "cancelled", "timed_out"]),
  reliability: z.enum([
    "verified_deterministic",
    "verified_ui_driven",
    "best_effort",
    "unsupported",
  ]),
  checks: z.array(checkSchema),
});

const axNodeSchema = z.object({
  id: z.string(),
  parentId: z.string().nullable(),
  role: z.string(),
  subrole: z.string().nullable(),
  identifier: z.string().nullable(),
  enabled: z.boolean().nullable(),
  focused: z.boolean().nullable(),
  childCount: z.number().int().nonnegative(),
});

const axOutputSchema = z.object({
  operationId: z.string(),
  status: z.enum(["succeeded", "partial", "failed", "cancelled", "timed_out"]),
  reliability: z.enum([
    "verified_deterministic",
    "verified_ui_driven",
    "best_effort",
    "unsupported",
  ]),
  application: z.object({
    bundleIdentifier: z.literal("com.apple.logic10"),
    pid: z.number().int().positive(),
  }),
  capturedAt: z.iso.datetime(),
  limits: z.object({
    maxDepth: z.number().int().min(0).max(8),
    maxNodes: z.number().int().min(1).max(1000),
  }),
  truncated: z.boolean(),
  nodes: z.array(axNodeSchema).max(1000),
  evidence: z.array(evidenceSchema).min(1),
});

const transportStateSchema = z.object({
  playing: z.enum(["playing", "stopped", "unknown"]),
  cycle: z.enum(["enabled", "disabled", "unknown"]),
  recordReady: z.enum(["ready", "not_ready", "unknown"]),
  observedAt: z.iso.datetime().nullable(),
});

const transportOutputSchema = z.object({
  operationId: z.string(),
  status: z.enum(["succeeded", "partial", "failed", "cancelled", "timed_out"]),
  reliability: z.enum([
    "verified_deterministic",
    "verified_ui_driven",
    "best_effort",
    "unsupported",
  ]),
  requestedState: z.enum(["playing", "stopped"]),
  commandDispatched: z.boolean(),
  state: transportStateSchema,
  evidence: z.array(evidenceSchema),
});

const transportPositionSchema = z.object({
  display: z.string().regex(/^\d{10}$/).nullable(),
  observedAt: z.iso.datetime().nullable(),
});

const transportLocationOutputSchema = z.object({
  operationId: z.string(),
  status: z.enum(["succeeded", "partial", "failed", "cancelled", "timed_out"]),
  reliability: z.enum([
    "verified_deterministic",
    "verified_ui_driven",
    "best_effort",
    "unsupported",
  ]),
  requestedDirection: z.enum(["backward", "forward"]),
  steps: z.number().int().min(1).max(100),
  commandDispatched: z.boolean(),
  initialPosition: transportPositionSchema,
  position: transportPositionSchema,
  evidence: z.array(evidenceSchema),
});

const transportLocateOutputSchema = z.object({
  operationId: z.string(),
  status: z.enum(["succeeded", "partial", "failed", "cancelled", "timed_out"]),
  reliability: z.enum([
    "verified_deterministic",
    "verified_ui_driven",
    "best_effort",
    "unsupported",
  ]),
  requestedTarget: z.literal("project_start"),
  commandDispatched: z.boolean(),
  initialPosition: transportPositionSchema,
  position: transportPositionSchema,
  evidence: z.array(evidenceSchema),
});

const projectIdentitySchema = z.object({
  name: z.string().min(1),
  path: z.string().min(1),
  modified: z.boolean(),
  observedAt: z.iso.datetime(),
});

const projectFailureSchema = z.enum([
  "fixture_not_found",
  "invalid_fixture",
  "user_project_open",
  "no_managed_project",
  "project_identity_changed",
  "unsaved_changes",
  "dialog_presented",
  "automation_denied",
  "command_failed",
  "postcondition_failed",
  "cleanup_failed",
]);

const projectOutputSchema = z.object({
  operationId: z.string(),
  status: z.enum(["succeeded", "partial", "failed", "cancelled", "timed_out"]),
  reliability: z.enum([
    "verified_deterministic",
    "verified_ui_driven",
    "best_effort",
    "unsupported",
  ]),
  action: z.enum(["observe", "open", "save", "close", "reopen", "cleanup"]),
  commandDispatched: z.boolean(),
  project: projectIdentitySchema.optional(),
  managedProjectPath: z.string().min(1).optional(),
  policyContext: z.boolean(),
  cleanupPerformed: z.boolean(),
  failure: projectFailureSchema.optional(),
  evidence: z.array(evidenceSchema),
});

const trackIdentitySchema = z.object({
  id: z.string().min(1),
  position: z.number().int().positive(),
  type: z.enum(["software_instrument", "audio", "external_midi", "unknown"]),
  name: z.string().min(1),
  selected: z.boolean(),
  observedAt: z.iso.datetime(),
});

const trackOutputSchema = z.object({
  operationId: z.string(),
  status: z.enum(["succeeded", "partial", "failed", "cancelled", "timed_out"]),
  reliability: z.enum(["verified_deterministic", "verified_ui_driven", "best_effort", "unsupported"]),
  action: z.enum(["observe", "create", "rename", "select", "duplicate", "reorder", "delete"]),
  commandDispatched: z.boolean(),
  policyContext: z.boolean(),
  targetTrackId: z.string().min(1).optional(),
  undoAvailable: z.boolean(),
  tracks: z.array(trackIdentitySchema),
  failure: z.enum([
    "project_policy_missing", "test_mode_inactive", "accessibility_unavailable",
    "logic_not_running", "logic_not_focused", "track_not_found", "unsupported_track_type",
    "invalid_name", "invalid_position", "confirmation_required", "dialog_presented",
    "command_failed", "postcondition_failed", "undo_unavailable",
  ]).optional(),
  evidence: z.array(evidenceSchema).min(1),
});

export function createLogicMcpServer({
  bridge,
  createOperationId = randomUUID,
  diagnosticsEnabled = false,
}: LogicMcpServerDependencies): McpServer {
  const server = new McpServer({
    name: "logic-llm-connector",
    version: "0.1.0",
  });

  server.registerTool(
    "logic_doctor",
    {
      title: "Diagnose Logic connector readiness",
      description:
        "Inspect Logic Pro, macOS permissions, and connector prerequisites without changing Logic.",
      inputSchema: z.object({}),
      outputSchema,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async () => {
      const result = await bridge.doctor({
        protocolVersion: BRIDGE_PROTOCOL_VERSION,
        operationId: createOperationId(),
      });
      const structuredContent = {
        operationId: result.operationId,
        status: result.status,
        reliability: result.reliability,
        checks: result.data.checks,
      };
      const summary = result.data.checks
        .map((check) => `${check.status.toUpperCase()}: ${check.summary}`)
        .join("\n");

      return {
        content: [{ type: "text", text: summary }],
        structuredContent,
      };
    },
  );

  const registerTransportTool = (
    name: "logic_play" | "logic_stop",
    playing: boolean,
  ) => server.registerTool(
    name,
    {
      title: playing ? "Play Logic transport" : "Stop Logic transport",
      description: playing
        ? "Start Logic playback and verify the playing state from Mackie Control feedback."
        : "Stop Logic playback and verify the stopped state from Mackie Control feedback.",
      inputSchema: z.object({
        timeoutMs: z.number().int().min(100).max(5000).default(1500),
      }),
      outputSchema: transportOutputSchema,
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async ({ timeoutMs }) => {
      const result = await bridge.setTransportPlaying({
        protocolVersion: BRIDGE_PROTOCOL_VERSION,
        operationId: createOperationId(),
        playing,
        timeoutMs,
      });
      const structuredContent = {
        operationId: result.operationId,
        status: result.status,
        reliability: result.reliability,
        requestedState: result.data.requestedState,
        commandDispatched: result.data.commandDispatched,
        state: result.data.state,
        evidence: result.evidence,
      };
      return {
        content: [{
          type: "text",
          text: `Logic transport is ${result.data.state.playing} (${result.status}).`,
        }],
        structuredContent,
      };
    },
  );

  registerTransportTool("logic_play", true);
  registerTransportTool("logic_stop", false);

  server.registerTool(
    "logic_move_playhead",
    {
      title: "Move Logic playhead",
      description:
        "Move the Logic playhead by bounded Mackie jog-wheel steps and verify the direction from position-display feedback.",
      inputSchema: z.object({
        direction: z.enum(["backward", "forward"]),
        steps: z.number().int().min(1).max(100).default(1),
        timeoutMs: z.number().int().min(100).max(5000).default(1500),
      }),
      outputSchema: transportLocationOutputSchema,
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false,
      },
    },
    async ({ direction, steps, timeoutMs }) => {
      const result = await bridge.moveTransportPlayhead({
        protocolVersion: BRIDGE_PROTOCOL_VERSION,
        operationId: createOperationId(),
        direction,
        steps,
        timeoutMs,
      });
      const structuredContent = {
        operationId: result.operationId,
        status: result.status,
        reliability: result.reliability,
        requestedDirection: result.data.requestedDirection,
        steps: result.data.steps,
        commandDispatched: result.data.commandDispatched,
        initialPosition: result.data.initialPosition,
        position: result.data.position,
        evidence: result.evidence,
      };
      return {
        content: [{
          type: "text",
          text: `Logic playhead position is ${result.data.position.display ?? "unknown"} (${result.status}).`,
        }],
        structuredContent,
      };
    },
  );

  server.registerTool(
    "logic_locate",
    {
      title: "Locate Logic transport",
      description:
        "Move the Logic playhead to a supported absolute target through Mackie Control and verify fresh position feedback while preserving observed Cycle state.",
      inputSchema: z.object({
        target: z.literal("project_start").default("project_start"),
        timeoutMs: z.number().int().min(100).max(5000).default(1500),
      }),
      outputSchema: transportLocateOutputSchema,
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async ({ target, timeoutMs }) => {
      const result = await bridge.locateTransport({
        protocolVersion: BRIDGE_PROTOCOL_VERSION,
        operationId: createOperationId(),
        target,
        timeoutMs,
      });
      const structuredContent = {
        operationId: result.operationId,
        status: result.status,
        reliability: result.reliability,
        requestedTarget: result.data.requestedTarget,
        commandDispatched: result.data.commandDispatched,
        initialPosition: result.data.initialPosition,
        position: result.data.position,
        evidence: result.evidence,
      };
      return {
        content: [{
          type: "text",
          text: `Logic playhead position is ${result.data.position.display ?? "unknown"} (${result.status}).`,
        }],
        structuredContent,
      };
    },
  );

  const projectResponse = (result: ProjectLifecycleResult) => {
    const structuredContent = {
      operationId: result.operationId,
      status: result.status,
      reliability: result.reliability,
      ...result.data,
      evidence: result.evidence,
    };
    const identity = result.data.project?.path ?? result.data.managedProjectPath ?? "no project";
    const detail = result.data.failure ? `: ${result.data.failure}` : "";
    return {
      content: [{
        type: "text" as const,
        text: `Logic Test Project ${result.data.action} ${result.status}${detail} (${identity}).`,
      }],
      structuredContent,
    };
  };

  server.registerTool(
    "logic_open_test_project",
    {
      title: "Open a copied Logic Test Project",
      description:
        "Copy a .logicx fixture into the connector's dedicated test directory, open only that copy, and verify its document identity.",
      inputSchema: z.object({
        fixturePath: z.string().min(1),
        timeoutMs: z.number().int().min(100).max(30_000).default(15_000),
      }),
      outputSchema: projectOutputSchema,
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false,
      },
    },
    async ({ fixturePath, timeoutMs }) => projectResponse(await bridge.openTestProject({
      protocolVersion: BRIDGE_PROTOCOL_VERSION,
      operationId: createOperationId(),
      fixturePath,
      timeoutMs,
    })),
  );

  server.registerTool(
    "logic_save_test_project",
    {
      title: "Save the active Logic Test Project",
      description:
        "Save only the verified managed Test Project and verify the same document is no longer modified. Requires explicit confirmation.",
      inputSchema: z.object({
        confirm: z.literal(true),
        timeoutMs: z.number().int().min(100).max(30_000).default(15_000),
      }),
      outputSchema: projectOutputSchema,
      annotations: {
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async ({ timeoutMs }) => projectResponse(await bridge.saveTestProject({
      protocolVersion: BRIDGE_PROTOCOL_VERSION,
      operationId: createOperationId(),
      timeoutMs,
    })),
  );

  server.registerTool(
    "logic_close_test_project",
    {
      title: "Close the active Logic Test Project",
      description:
        "Close only the verified managed Test Project after rejecting unsaved changes, then verify that no Logic document remains open.",
      inputSchema: z.object({
        timeoutMs: z.number().int().min(100).max(30_000).default(15_000),
      }),
      outputSchema: projectOutputSchema,
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false,
      },
    },
    async ({ timeoutMs }) => projectResponse(await bridge.closeTestProject({
      protocolVersion: BRIDGE_PROTOCOL_VERSION,
      operationId: createOperationId(),
      timeoutMs,
    })),
  );

  server.registerTool(
    "logic_reopen_test_project",
    {
      title: "Reopen the managed Logic Test Project",
      description:
        "Reopen the last managed Test Project only when no Logic document is open and verify its document identity.",
      inputSchema: z.object({
        timeoutMs: z.number().int().min(100).max(30_000).default(15_000),
      }),
      outputSchema: projectOutputSchema,
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false,
      },
    },
    async ({ timeoutMs }) => projectResponse(await bridge.reopenTestProject({
      protocolVersion: BRIDGE_PROTOCOL_VERSION,
      operationId: createOperationId(),
      timeoutMs,
    })),
  );

  server.registerTool(
    "logic_cleanup_test_project",
    {
      title: "Clean up the managed Logic Test Project",
      description:
        "Close the verified managed Test Project without saving and delete only its connector-owned copied workspace. Requires explicit confirmation.",
      inputSchema: z.object({
        confirm: z.literal(true),
        timeoutMs: z.number().int().min(100).max(30_000).default(15_000),
      }),
      outputSchema: projectOutputSchema,
      annotations: {
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async ({ timeoutMs }) => projectResponse(await bridge.cleanupTestProject({
      protocolVersion: BRIDGE_PROTOCOL_VERSION,
      operationId: createOperationId(),
      timeoutMs,
    })),
  );

  const trackResponse = (result: TrackOperationResult) => {
    const structuredContent = {
      operationId: result.operationId,
      status: result.status,
      reliability: result.reliability,
      ...result.data,
      evidence: result.evidence,
    };
    const detail = result.data.failure ? `: ${result.data.failure}` : "";
    return {
      content: [{
        type: "text" as const,
        text: `Logic tracks ${result.data.action} ${result.status}${detail}; observed ${result.data.tracks.length} track(s).`,
      }],
      structuredContent,
    };
  };
  const trackIdInput = z.string().min(1);
  const trackNameInput = z.string().trim().min(1).max(128);
  const trackTimeoutInput = z.number().int().min(100).max(10_000).default(2_000);

  server.registerTool(
    "logic_list_tracks",
    {
      title: "Inspect Logic tracks",
      description: "Observe ordered track IDs, names, supported types, and selection in the verified managed Test Project.",
      inputSchema: z.object({}),
      outputSchema: trackOutputSchema,
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () => trackResponse(await bridge.trackState({
      protocolVersion: BRIDGE_PROTOCOL_VERSION,
      operationId: createOperationId(),
    })),
  );

  server.registerTool(
    "logic_create_track",
    {
      title: "Create a Logic track",
      description: "Create one Audio, Software Instrument, or External MIDI track in the managed Test Project and verify count, type, name, and selection. Requires active Exclusive Test Mode.",
      inputSchema: z.object({
        type: z.enum(["software_instrument", "audio", "external_midi"]),
        name: trackNameInput.optional(),
        timeoutMs: trackTimeoutInput,
      }),
      outputSchema: trackOutputSchema,
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async ({ type, name, timeoutMs }) => trackResponse(await bridge.createTrack({
      protocolVersion: BRIDGE_PROTOCOL_VERSION, operationId: createOperationId(), type,
      ...(name === undefined ? {} : { name }), timeoutMs,
    })),
  );

  server.registerTool(
    "logic_rename_track",
    {
      title: "Rename a Logic track",
      description: "Rename an opaque track ID and verify that the same track identity has the requested name. Requires active Exclusive Test Mode.",
      inputSchema: z.object({ trackId: trackIdInput, name: trackNameInput, timeoutMs: trackTimeoutInput }),
      outputSchema: trackOutputSchema,
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async ({ trackId, name, timeoutMs }) => trackResponse(await bridge.renameTrack({
      protocolVersion: BRIDGE_PROTOCOL_VERSION, operationId: createOperationId(), trackId, name, timeoutMs,
    })),
  );

  server.registerTool(
    "logic_select_track",
    {
      title: "Select a Logic track",
      description: "Select an opaque track ID and verify its selected state. Requires active Exclusive Test Mode.",
      inputSchema: z.object({ trackId: trackIdInput, timeoutMs: trackTimeoutInput }),
      outputSchema: trackOutputSchema,
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async ({ trackId, timeoutMs }) => trackResponse(await bridge.selectTrack({
      protocolVersion: BRIDGE_PROTOCOL_VERSION, operationId: createOperationId(), trackId, timeoutMs,
    })),
  );

  server.registerTool(
    "logic_duplicate_track",
    {
      title: "Duplicate a Logic track",
      description: "Create an empty track with the selected track's settings and verify both identities and the duplicate's selection. Requires active Exclusive Test Mode.",
      inputSchema: z.object({ trackId: trackIdInput, name: trackNameInput.optional(), timeoutMs: trackTimeoutInput }),
      outputSchema: trackOutputSchema,
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async ({ trackId, name, timeoutMs }) => trackResponse(await bridge.duplicateTrack({
      protocolVersion: BRIDGE_PROTOCOL_VERSION, operationId: createOperationId(), trackId,
      ...(name === undefined ? {} : { name }), timeoutMs,
    })),
  );

  server.registerTool(
    "logic_reorder_track",
    {
      title: "Reorder a Logic track",
      description: "Move an opaque track ID to a 1-based track position and verify identity and order. Requires active Exclusive Test Mode and Logic focus.",
      inputSchema: z.object({ trackId: trackIdInput, position: z.number().int().positive(), timeoutMs: trackTimeoutInput }),
      outputSchema: trackOutputSchema,
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async ({ trackId, position, timeoutMs }) => trackResponse(await bridge.reorderTrack({
      protocolVersion: BRIDGE_PROTOCOL_VERSION, operationId: createOperationId(), trackId, position, timeoutMs,
    })),
  );

  server.registerTool(
    "logic_delete_track",
    {
      title: "Delete a Logic track",
      description: "Delete one opaque track ID only in the managed Test Project, then verify its removal and that Logic offers Undo Delete Track. Requires active Exclusive Test Mode and explicit confirmation.",
      inputSchema: z.object({ trackId: trackIdInput, confirm: z.literal(true), timeoutMs: trackTimeoutInput }),
      outputSchema: trackOutputSchema,
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false },
    },
    async ({ trackId, timeoutMs }) => trackResponse(await bridge.deleteTrack({
      protocolVersion: BRIDGE_PROTOCOL_VERSION, operationId: createOperationId(), trackId, confirm: true, timeoutMs,
    })),
  );

  server.registerResource(
    "logic_transport_state",
    "logic://transport/state",
    {
      title: "Logic transport state",
      description: "Observed playback, cycle, and record-readiness state from Mackie Control feedback.",
      mimeType: "application/json",
    },
    async (uri) => {
      const result = await bridge.transportState({
        protocolVersion: BRIDGE_PROTOCOL_VERSION,
        operationId: createOperationId(),
      });
      return {
        contents: [{
          uri: uri.href,
          mimeType: "application/json",
          text: JSON.stringify({
            operationId: result.operationId,
            status: result.status,
            reliability: result.reliability,
            state: result.data,
            evidence: result.evidence,
          }),
        }],
      };
    },
  );

  server.registerResource(
    "logic_project_state",
    "logic://project/state",
    {
      title: "Logic project state",
      description: "Observed front-document identity and verified Test Project policy context.",
      mimeType: "application/json",
    },
    async (uri) => {
      const result = await bridge.projectState({
        protocolVersion: BRIDGE_PROTOCOL_VERSION,
        operationId: createOperationId(),
      });
      return {
        contents: [{
          uri: uri.href,
          mimeType: "application/json",
          text: JSON.stringify({
            operationId: result.operationId,
            status: result.status,
            reliability: result.reliability,
            state: result.data,
            evidence: result.evidence,
          }),
        }],
      };
    },
  );

  server.registerResource(
    "logic_tracks_state",
    "logic://tracks/state",
    {
      title: "Logic tracks state",
      description: "Observed ordered track identities, names, types, and selection in the managed Test Project.",
      mimeType: "application/json",
    },
    async (uri) => {
      const result = await bridge.trackState({
        protocolVersion: BRIDGE_PROTOCOL_VERSION,
        operationId: createOperationId(),
      });
      return { contents: [{
        uri: uri.href,
        mimeType: "application/json",
        text: JSON.stringify({
          operationId: result.operationId,
          status: result.status,
          reliability: result.reliability,
          state: result.data,
          evidence: result.evidence,
        }),
      }] };
    },
  );

  if (diagnosticsEnabled) {
    server.registerTool(
      "logic_inspect_ui",
      {
        title: "Inspect Logic UI structure",
        description:
          "Return a bounded, text-free Accessibility structure for diagnostics. Never performs UI actions.",
        inputSchema: z.object({
          maxDepth: z.number().int().min(0).max(8).default(3),
          maxNodes: z.number().int().min(1).max(1000).default(200),
        }),
        outputSchema: axOutputSchema,
        annotations: {
          readOnlyHint: true,
          destructiveHint: false,
          idempotentHint: true,
          openWorldHint: false,
        },
      },
      async ({ maxDepth, maxNodes }) => {
        const result = await bridge.inspectUI({
          protocolVersion: BRIDGE_PROTOCOL_VERSION,
          operationId: createOperationId(),
          maxDepth,
          maxNodes,
        });
        const structuredContent = {
          operationId: result.operationId,
          status: result.status,
          reliability: result.reliability,
          application: result.data.application,
          capturedAt: result.data.capturedAt,
          limits: result.data.limits,
          truncated: result.data.truncated,
          nodes: result.data.nodes,
          evidence: result.evidence,
        };

        return {
          content: [
            {
              type: "text",
              text: `Observed ${result.data.nodes.length} Logic UI nodes${
                result.data.truncated ? " (truncated)" : ""
              }.`,
            },
          ],
          structuredContent,
        };
      },
    );
  }

  return server;
}
