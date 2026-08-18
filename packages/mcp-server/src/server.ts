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
