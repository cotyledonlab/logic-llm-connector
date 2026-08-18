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

export interface LogicBridge {
  doctor(request: {
    protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
    operationId: string;
  }): Promise<DoctorResult>;
}

export interface LogicMcpServerDependencies {
  bridge: LogicBridge;
  createOperationId?: () => string;
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

export function createLogicMcpServer({
  bridge,
  createOperationId = randomUUID,
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

  return server;
}
