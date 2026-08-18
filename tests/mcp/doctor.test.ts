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
    async inspectUI() {
      throw new Error("UI inspection is not used in this test");
    },
    async transportState() {
      throw new Error("transport is not used in this test");
    },
    async setTransportPlaying() {
      throw new Error("transport is not used in this test");
    },
    async moveTransportPlayhead() {
      throw new Error("transport is not used in this test");
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
  assert.deepEqual(listed.tools.map((tool) => tool.name), [
    "logic_doctor",
    "logic_play",
    "logic_stop",
    "logic_move_playhead",
  ]);

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

test("UI inspection is absent by default and available only when enabled", async (t) => {
  const calls: unknown[] = [];
  const bridge: LogicBridge = {
    async doctor() {
      throw new Error("doctor is not used in this test");
    },
    async inspectUI(request) {
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
          application: { bundleIdentifier: "com.apple.logic10", pid: 42 },
          capturedAt: timestamp,
          limits: { maxDepth: request.maxDepth, maxNodes: request.maxNodes },
          truncated: false,
          nodes: [
            {
              id: "node-0",
              parentId: null,
              role: "AXApplication",
              subrole: null,
              identifier: null,
              enabled: true,
              focused: false,
              childCount: 1,
            },
          ],
        },
        evidence: [
          {
            source: "AXUIElement",
            observedAt: timestamp,
            value: { nodeCount: 1, truncated: false },
          },
        ],
      };
    },
    async transportState() {
      throw new Error("transport is not used in this test");
    },
    async setTransportPlaying() {
      throw new Error("transport is not used in this test");
    },
    async moveTransportPlayhead() {
      throw new Error("transport is not used in this test");
    },
  };
  const disabledServer = createLogicMcpServer({
    bridge,
    createOperationId: () => "inspect-disabled",
  });
  const [disabledClientTransport, disabledServerTransport] =
    InMemoryTransport.createLinkedPair();
  const disabledClient = new Client({ name: "disabled-client", version: "1.0.0" });
  await disabledServer.connect(disabledServerTransport);
  await disabledClient.connect(disabledClientTransport);
  assert.deepEqual((await disabledClient.listTools()).tools.map((tool) => tool.name), [
    "logic_doctor",
    "logic_play",
    "logic_stop",
    "logic_move_playhead",
  ]);
  await disabledClient.close();
  await disabledServer.close();

  const server = createLogicMcpServer({
    bridge,
    createOperationId: () => "inspect-1",
    diagnosticsEnabled: true,
  });
  const client = new Client({ name: "enabled-client", version: "1.0.0" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  t.after(async () => {
    await client.close();
    await server.close();
  });

  assert.deepEqual((await client.listTools()).tools.map((tool) => tool.name), [
    "logic_doctor",
    "logic_play",
    "logic_stop",
    "logic_move_playhead",
    "logic_inspect_ui",
  ]);
  const result = await client.callTool({
    name: "logic_inspect_ui",
    arguments: { maxDepth: 2, maxNodes: 50 },
  });
  assert.equal(result.isError, undefined);
  const structuredContent = result.structuredContent as
    | Record<string, unknown>
    | undefined;
  assert.deepEqual(structuredContent?.["nodes"], [
    {
      id: "node-0",
      parentId: null,
      role: "AXApplication",
      subrole: null,
      identifier: null,
      enabled: true,
      focused: false,
      childCount: 1,
    },
  ]);
  assert.deepEqual(calls, [
    {
      protocolVersion: "1.0.0",
      operationId: "inspect-1",
      maxDepth: 2,
      maxNodes: 50,
    },
  ]);
});

test("transport tools and resource preserve verified native outcomes", async (t) => {
  const calls: unknown[] = [];
  const timestamp = "2026-08-18T10:00:00.000Z";
  const state = {
    playing: "playing" as const,
    cycle: "disabled" as const,
    recordReady: "not_ready" as const,
    observedAt: timestamp,
  };
  const bridge: LogicBridge = {
    async doctor() { throw new Error("unused"); },
    async inspectUI() { throw new Error("unused"); },
    async transportState(request) {
      calls.push(request);
      return {
        protocolVersion: "1.0.0",
        operationId: request.operationId,
        status: "succeeded",
        reliability: "verified_deterministic",
        startedAt: timestamp,
        finishedAt: timestamp,
        data: state,
        evidence: [{ source: "Mackie Control feedback", observedAt: timestamp, value: state }],
      };
    },
    async setTransportPlaying(request) {
      calls.push(request);
      return {
        protocolVersion: "1.0.0",
        operationId: request.operationId,
        status: "succeeded",
        reliability: "verified_deterministic",
        startedAt: timestamp,
        finishedAt: timestamp,
        data: {
          requestedState: request.playing ? "playing" : "stopped",
          commandDispatched: true,
          state: { ...state, playing: request.playing ? "playing" : "stopped" },
        },
        evidence: [{ source: "Mackie Control feedback", observedAt: timestamp, value: state }],
      };
    },
    async moveTransportPlayhead(request) {
      calls.push(request);
      return {
        protocolVersion: "1.0.0",
        operationId: request.operationId,
        status: "succeeded",
        reliability: "verified_deterministic",
        startedAt: timestamp,
        finishedAt: timestamp,
        data: {
          requestedDirection: request.direction,
          steps: request.steps,
          commandDispatched: true,
          initialPosition: { display: "0000000100", observedAt: timestamp },
          position: { display: "0000000101", observedAt: timestamp },
        },
        evidence: [{
          source: "Mackie Control position feedback",
          observedAt: timestamp,
          value: { display: "0000000101" },
        }],
      };
    },
  };
  let operation = 0;
  const server = createLogicMcpServer({
    bridge,
    createOperationId: () => `transport-${++operation}`,
  });
  const client = new Client({ name: "transport-client", version: "1.0.0" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  t.after(async () => { await client.close(); await server.close(); });

  const play = await client.callTool({
    name: "logic_play",
    arguments: { timeoutMs: 750 },
  });
  assert.equal(play.isError, undefined);
  assert.equal((play.structuredContent as Record<string, unknown>)["requestedState"], "playing");

  const move = await client.callTool({
    name: "logic_move_playhead",
    arguments: { direction: "forward", steps: 1, timeoutMs: 750 },
  });
  assert.equal(move.isError, undefined);
  assert.deepEqual(move.structuredContent, {
    operationId: "transport-2",
    status: "succeeded",
    reliability: "verified_deterministic",
    requestedDirection: "forward",
    steps: 1,
    commandDispatched: true,
    initialPosition: { display: "0000000100", observedAt: timestamp },
    position: { display: "0000000101", observedAt: timestamp },
    evidence: [{
      source: "Mackie Control position feedback",
      observedAt: timestamp,
      value: { display: "0000000101" },
    }],
  });

  const resource = await client.readResource({ uri: "logic://transport/state" });
  const resourceContent = resource.contents[0];
  assert.ok(resourceContent && "text" in resourceContent);
  assert.deepEqual(JSON.parse(resourceContent.text), {
    operationId: "transport-3",
    status: "succeeded",
    reliability: "verified_deterministic",
    state,
    evidence: [{ source: "Mackie Control feedback", observedAt: timestamp, value: state }],
  });
  assert.deepEqual(calls, [
    {
      protocolVersion: "1.0.0",
      operationId: "transport-1",
      playing: true,
      timeoutMs: 750,
    },
    {
      protocolVersion: "1.0.0",
      operationId: "transport-2",
      direction: "forward",
      steps: 1,
      timeoutMs: 750,
    },
    { protocolVersion: "1.0.0", operationId: "transport-3" },
  ]);
});
