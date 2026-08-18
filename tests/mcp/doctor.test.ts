import assert from "node:assert/strict";
import test from "node:test";

import { Client } from "@modelcontextprotocol/client";
import { InMemoryTransport } from "@modelcontextprotocol/server";

import {
  createLogicMcpServer,
  type LogicBridge,
} from "../../packages/mcp-server/src/server.js";

test("an MCP client can diagnose Logic readiness", async (t) => {
  const calls: unknown[] = [];
  const bridge: LogicBridge = {
    async doctor(request) {
      calls.push(request);
      const timestamp = "2026-08-18T10:00:00.000Z";
      return {
        protocolVersion: "1.0.0",
        operationId: request.operationId,
        status: "succeeded",
        reliability: "verified_deterministic",
        startedAt: timestamp,
        finishedAt: timestamp,
        data: {
          checks: [
            {
              id: "logic.application",
              status: "passed",
              summary: "Logic Pro 12.3 is running",
              evidence: [
                {
                  source: "NSWorkspace",
                  observedAt: timestamp,
                  value: { version: "12.3", running: true },
                },
              ],
            },
          ],
        },
        evidence: [
          {
            source: "NSWorkspace",
            observedAt: timestamp,
            value: { bundleIdentifier: "com.apple.logic10" },
          },
        ],
      };
    },
  };

  const server = createLogicMcpServer({ bridge, createOperationId: () => "op-1" });
  const client = new Client({ name: "test-client", version: "1.0.0" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();

  await server.connect(serverTransport);
  await client.connect(clientTransport);
  t.after(async () => {
    await client.close();
    await server.close();
  });

  const listed = await client.listTools();
  assert.deepEqual(listed.tools.map((tool) => tool.name), ["logic_doctor"]);

  const result = await client.callTool({ name: "logic_doctor", arguments: {} });
  assert.equal(result.isError, undefined);
  assert.deepEqual(result.structuredContent, {
    operationId: "op-1",
    status: "succeeded",
    reliability: "verified_deterministic",
    checks: [
      {
        id: "logic.application",
        status: "passed",
        summary: "Logic Pro 12.3 is running",
        evidence: [
          {
            source: "NSWorkspace",
            observedAt: "2026-08-18T10:00:00.000Z",
            value: { version: "12.3", running: true },
          },
        ],
      },
    ],
  });
  assert.deepEqual(calls, [{ protocolVersion: "1.0.0", operationId: "op-1" }]);
});
