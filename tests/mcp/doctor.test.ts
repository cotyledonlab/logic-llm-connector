import assert from "node:assert/strict";
import test from "node:test";

import { Client } from "@modelcontextprotocol/client";
import { InMemoryTransport } from "@modelcontextprotocol/server";

import {
  createLogicMcpServer,
  type LogicBridge,
} from "../../packages/mcp-server/src/server.js";

const unusedProjectBridge = {
  async projectState() { throw new Error("project lifecycle is not used in this test"); },
  async openTestProject() { throw new Error("project lifecycle is not used in this test"); },
  async saveTestProject() { throw new Error("project lifecycle is not used in this test"); },
  async closeTestProject() { throw new Error("project lifecycle is not used in this test"); },
  async reopenTestProject() { throw new Error("project lifecycle is not used in this test"); },
  async cleanupTestProject() { throw new Error("project lifecycle is not used in this test"); },
} satisfies Pick<
  LogicBridge,
  | "projectState"
  | "openTestProject"
  | "saveTestProject"
  | "closeTestProject"
  | "reopenTestProject"
  | "cleanupTestProject"
>;

test("an MCP client can diagnose Logic readiness", async (t) => {
  const calls: unknown[] = [];
  const bridge: LogicBridge = {
    ...unusedProjectBridge,
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
    async locateTransport() {
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
    "logic_locate",
    "logic_open_test_project",
    "logic_save_test_project",
    "logic_close_test_project",
    "logic_reopen_test_project",
    "logic_cleanup_test_project",
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
    ...unusedProjectBridge,
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
    async locateTransport() {
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
    "logic_locate",
    "logic_open_test_project",
    "logic_save_test_project",
    "logic_close_test_project",
    "logic_reopen_test_project",
    "logic_cleanup_test_project",
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
    "logic_locate",
    "logic_open_test_project",
    "logic_save_test_project",
    "logic_close_test_project",
    "logic_reopen_test_project",
    "logic_cleanup_test_project",
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
    ...unusedProjectBridge,
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
    async locateTransport(request) {
      calls.push(request);
      return {
        protocolVersion: "1.0.0",
        operationId: request.operationId,
        status: "succeeded",
        reliability: "verified_deterministic",
        startedAt: timestamp,
        finishedAt: timestamp,
        data: {
          requestedTarget: request.target,
          commandDispatched: true,
          initialPosition: { display: "0000000101", observedAt: timestamp },
          position: { display: "0000000100", observedAt: timestamp },
        },
        evidence: [{
          source: "Mackie Control position feedback",
          observedAt: timestamp,
          value: { display: "0000000100", target: "project_start" },
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

  const locate = await client.callTool({
    name: "logic_locate",
    arguments: { target: "project_start", timeoutMs: 750 },
  });
  assert.equal(locate.isError, undefined);
  assert.deepEqual(locate.structuredContent, {
    operationId: "transport-3",
    status: "succeeded",
    reliability: "verified_deterministic",
    requestedTarget: "project_start",
    commandDispatched: true,
    initialPosition: { display: "0000000101", observedAt: timestamp },
    position: { display: "0000000100", observedAt: timestamp },
    evidence: [{
      source: "Mackie Control position feedback",
      observedAt: timestamp,
      value: { display: "0000000100", target: "project_start" },
    }],
  });

  const resource = await client.readResource({ uri: "logic://transport/state" });
  const resourceContent = resource.contents[0];
  assert.ok(resourceContent && "text" in resourceContent);
  assert.deepEqual(JSON.parse(resourceContent.text), {
    operationId: "transport-4",
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
    {
      protocolVersion: "1.0.0",
      operationId: "transport-3",
      target: "project_start",
      timeoutMs: 750,
    },
    { protocolVersion: "1.0.0", operationId: "transport-4" },
  ]);
});

test("project tools preserve copied-project identity, confirmation, and cleanup evidence", async (t) => {
  const calls: Array<{ method: string; request: unknown }> = [];
  const timestamp = "2026-08-19T10:00:00.000Z";
  const project = {
    name: "Fixture",
    path: "/managed/copy-1/Fixture.logicx",
    modified: false,
    observedAt: timestamp,
  };
  const makeResult = (
    operationId: string,
    action: "observe" | "open" | "save" | "close" | "reopen" | "cleanup",
  ) => ({
    protocolVersion: "1.0.0" as const,
    operationId,
    status: "succeeded" as const,
    reliability: "verified_deterministic" as const,
    startedAt: timestamp,
    finishedAt: timestamp,
    data: {
      action,
      commandDispatched: action !== "observe",
      ...(action === "close" || action === "cleanup" ? {} : { project }),
      ...(action === "cleanup" ? {} : { managedProjectPath: project.path }),
      policyContext: !["close", "cleanup"].includes(action),
      cleanupPerformed: action === "cleanup",
    },
    evidence: [{
      source: "Logic Apple Events document observation",
      observedAt: timestamp,
      value: { path: project.path },
    }],
  });
  const bridge: LogicBridge = {
    async doctor() { throw new Error("unused"); },
    async inspectUI() { throw new Error("unused"); },
    async transportState() { throw new Error("unused"); },
    async setTransportPlaying() { throw new Error("unused"); },
    async moveTransportPlayhead() { throw new Error("unused"); },
    async locateTransport() { throw new Error("unused"); },
    async projectState(request) {
      calls.push({ method: "state", request });
      return makeResult(request.operationId, "observe");
    },
    async openTestProject(request) {
      calls.push({ method: "open", request });
      return makeResult(request.operationId, "open");
    },
    async saveTestProject(request) {
      calls.push({ method: "save", request });
      return makeResult(request.operationId, "save");
    },
    async closeTestProject(request) {
      calls.push({ method: "close", request });
      return makeResult(request.operationId, "close");
    },
    async reopenTestProject(request) {
      calls.push({ method: "reopen", request });
      return makeResult(request.operationId, "reopen");
    },
    async cleanupTestProject(request) {
      calls.push({ method: "cleanup", request });
      return makeResult(request.operationId, "cleanup");
    },
  };
  let operation = 0;
  const server = createLogicMcpServer({
    bridge,
    createOperationId: () => `project-${++operation}`,
  });
  const client = new Client({ name: "project-client", version: "1.0.0" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  t.after(async () => { await client.close(); await server.close(); });

  const opened = await client.callTool({
    name: "logic_open_test_project",
    arguments: { fixturePath: "/fixtures/Fixture.logicx", timeoutMs: 5000 },
  });
  assert.equal(opened.isError, undefined);
  assert.equal((opened.structuredContent as Record<string, unknown>)["policyContext"], true);

  const deniedSave = await client.callTool({
    name: "logic_save_test_project",
    arguments: { timeoutMs: 5000 },
  });
  assert.equal(deniedSave.isError, true);

  const saved = await client.callTool({
    name: "logic_save_test_project",
    arguments: { confirm: true, timeoutMs: 5000 },
  });
  assert.equal(saved.isError, undefined);

  await client.callTool({ name: "logic_close_test_project", arguments: { timeoutMs: 5000 } });
  await client.callTool({ name: "logic_reopen_test_project", arguments: { timeoutMs: 5000 } });
  const cleaned = await client.callTool({
    name: "logic_cleanup_test_project",
    arguments: { confirm: true, timeoutMs: 5000 },
  });
  assert.equal((cleaned.structuredContent as Record<string, unknown>)["cleanupPerformed"], true);

  const resource = await client.readResource({ uri: "logic://project/state" });
  const content = resource.contents[0];
  assert.ok(content && "text" in content);
  assert.equal(JSON.parse(content.text).state.project.path, project.path);
  assert.deepEqual(calls.map(({ method }) => method), [
    "open", "save", "close", "reopen", "cleanup", "state",
  ]);
});
