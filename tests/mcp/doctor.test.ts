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

const unusedTrackBridge = {
  async trackState() { throw new Error("track operations are not used in this test"); },
  async createTrack() { throw new Error("track operations are not used in this test"); },
  async renameTrack() { throw new Error("track operations are not used in this test"); },
  async selectTrack() { throw new Error("track operations are not used in this test"); },
  async duplicateTrack() { throw new Error("track operations are not used in this test"); },
  async reorderTrack() { throw new Error("track operations are not used in this test"); },
  async deleteTrack() { throw new Error("track operations are not used in this test"); },
} satisfies Pick<
  LogicBridge,
  | "trackState" | "createTrack" | "renameTrack" | "selectTrack"
  | "duplicateTrack" | "reorderTrack" | "deleteTrack"
>;

const unusedMIDIBridge = {
  async midiRegionState() { throw new Error("MIDI region operations are not used in this test"); },
  async createMIDIRegion() { throw new Error("MIDI region operations are not used in this test"); },
  async renameMIDIRegion() { throw new Error("MIDI region operations are not used in this test"); },
  async moveMIDIRegion() { throw new Error("MIDI region operations are not used in this test"); },
  async resizeMIDIRegion() { throw new Error("MIDI region operations are not used in this test"); },
  async duplicateMIDIRegion() { throw new Error("MIDI region operations are not used in this test"); },
  async splitMIDIRegion() { throw new Error("MIDI region operations are not used in this test"); },
  async updateMIDINote() { throw new Error("MIDI region operations are not used in this test"); },
  async replaceMIDINotes() { throw new Error("MIDI region operations are not used in this test"); },
  async deleteMIDIRegion() { throw new Error("MIDI region operations are not used in this test"); },
  async verifyMIDIRegionPlayback() { throw new Error("MIDI region operations are not used in this test"); },
} satisfies Pick<
  LogicBridge,
  | "midiRegionState" | "createMIDIRegion" | "renameMIDIRegion" | "moveMIDIRegion"
  | "resizeMIDIRegion" | "duplicateMIDIRegion" | "splitMIDIRegion" | "updateMIDINote"
  | "replaceMIDINotes" | "deleteMIDIRegion" | "verifyMIDIRegionPlayback"
>;

test("an MCP client can diagnose Logic readiness", async (t) => {
  const calls: unknown[] = [];
  const bridge: LogicBridge = {
    ...unusedProjectBridge,
    ...unusedTrackBridge,
    ...unusedMIDIBridge,
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
    "logic_list_tracks",
    "logic_create_track",
    "logic_rename_track",
    "logic_select_track",
    "logic_duplicate_track",
    "logic_reorder_track",
    "logic_delete_track",
    "logic_list_midi_regions",
    "logic_create_midi_region",
    "logic_rename_midi_region",
    "logic_move_midi_region",
    "logic_duplicate_midi_region",
    "logic_split_midi_region",
    "logic_resize_midi_region",
    "logic_update_midi_note",
    "logic_replace_midi_notes",
    "logic_delete_midi_region",
    "logic_verify_midi_region_playback",
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
    ...unusedTrackBridge,
    ...unusedMIDIBridge,
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
    "logic_list_tracks",
    "logic_create_track",
    "logic_rename_track",
    "logic_select_track",
    "logic_duplicate_track",
    "logic_reorder_track",
    "logic_delete_track",
    "logic_list_midi_regions",
    "logic_create_midi_region",
    "logic_rename_midi_region",
    "logic_move_midi_region",
    "logic_duplicate_midi_region",
    "logic_split_midi_region",
    "logic_resize_midi_region",
    "logic_update_midi_note",
    "logic_replace_midi_notes",
    "logic_delete_midi_region",
    "logic_verify_midi_region_playback",
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
    "logic_list_tracks",
    "logic_create_track",
    "logic_rename_track",
    "logic_select_track",
    "logic_duplicate_track",
    "logic_reorder_track",
    "logic_delete_track",
    "logic_list_midi_regions",
    "logic_create_midi_region",
    "logic_rename_midi_region",
    "logic_move_midi_region",
    "logic_duplicate_midi_region",
    "logic_split_midi_region",
    "logic_resize_midi_region",
    "logic_update_midi_note",
    "logic_replace_midi_notes",
    "logic_delete_midi_region",
    "logic_verify_midi_region_playback",
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
    ...unusedTrackBridge,
    ...unusedMIDIBridge,
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
    ...unusedTrackBridge,
    ...unusedMIDIBridge,
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

test("track tools preserve opaque identity, safety confirmation, and observed state", async (t) => {
  const calls: Array<{ method: string; request: unknown }> = [];
  const timestamp = "2026-08-19T10:00:00.000Z";
  const makeResult = (operationId: string, action: "observe" | "create" | "delete") => ({
    protocolVersion: "1.0.0" as const,
    operationId,
    status: "succeeded" as const,
    reliability: "verified_ui_driven" as const,
    startedAt: timestamp,
    finishedAt: timestamp,
    data: {
      action,
      commandDispatched: action !== "observe",
      policyContext: true,
      ...(action === "observe" ? {} : { targetTrackId: "track-a" }),
      undoAvailable: action === "delete",
      tracks: action === "delete" ? [] : [{
        id: "track-a", position: 1, type: "audio" as const, name: "Voice",
        selected: true, observedAt: timestamp,
      }],
    },
    evidence: [{ source: "AX track headers", observedAt: timestamp, value: { trackCount: action === "delete" ? 0 : 1 } }],
  });
  const unused = async () => { throw new Error("unused"); };
  const bridge: LogicBridge = {
    ...unusedProjectBridge,
    ...unusedMIDIBridge,
    doctor: unused,
    inspectUI: unused,
    transportState: unused,
    setTransportPlaying: unused,
    moveTransportPlayhead: unused,
    locateTransport: unused,
    async trackState(request) { calls.push({ method: "state", request }); return makeResult(request.operationId, "observe"); },
    async createTrack(request) { calls.push({ method: "create", request }); return makeResult(request.operationId, "create"); },
    renameTrack: unused,
    selectTrack: unused,
    duplicateTrack: unused,
    reorderTrack: unused,
    async deleteTrack(request) { calls.push({ method: "delete", request }); return makeResult(request.operationId, "delete"); },
  };
  let operation = 0;
  const server = createLogicMcpServer({ bridge, createOperationId: () => `track-${++operation}` });
  const client = new Client({ name: "track-client", version: "1.0.0" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  t.after(async () => { await client.close(); await server.close(); });

  const created = await client.callTool({
    name: "logic_create_track",
    arguments: { type: "audio", name: "Voice", timeoutMs: 1000 },
  });
  assert.equal(created.isError, undefined);
  assert.equal((created.structuredContent as Record<string, unknown>)["targetTrackId"], "track-a");

  const deniedDelete = await client.callTool({
    name: "logic_delete_track",
    arguments: { trackId: "track-a", timeoutMs: 1000 },
  });
  assert.equal(deniedDelete.isError, true);

  const deleted = await client.callTool({
    name: "logic_delete_track",
    arguments: { trackId: "track-a", confirm: true, timeoutMs: 1000 },
  });
  assert.equal((deleted.structuredContent as Record<string, unknown>)["undoAvailable"], true);

  const resource = await client.readResource({ uri: "logic://tracks/state" });
  const content = resource.contents[0];
  assert.ok(content && "text" in content);
  assert.equal(JSON.parse(content.text).state.tracks[0].id, "track-a");
  assert.deepEqual(calls.map(({ method }) => method), ["create", "delete", "state"]);
});

test("MIDI tools preserve explicit time, note fidelity, confirmation, and observed resources", async (t) => {
  const calls: Array<{ method: string; request: unknown }> = [];
  const timestamp = "2026-08-22T10:00:00.000Z";
  const region = {
    id: "region-a", trackId: "track-a", name: "Four Bars",
    position: { ticks: 3840, ppq: 960 as const },
    length: { ticks: 15360, ppq: 960 as const },
    notes: [{
      id: "note-a", pitch: 60,
      onset: { ticks: 0, ppq: 960 as const },
      duration: { ticks: 960, ppq: 960 as const },
      velocity: 100, channel: 1,
    }],
    selected: true, active: true, observedAt: timestamp,
  };
  const makeResult = (
    operationId: string,
    action: "observe" | "create" | "update_note" | "delete" | "verify_playback",
  ) => ({
    protocolVersion: "1.0.0" as const,
    operationId,
    status: "succeeded" as const,
    reliability: "verified_ui_driven" as const,
    startedAt: timestamp,
    finishedAt: timestamp,
    data: {
      action,
      commandDispatched: action !== "observe",
      policyContext: true,
      ...(action === "observe" ? {} : { targetRegionId: "region-a" }),
      createdRegionIds: action === "create" ? ["region-a"] : [],
      exactFidelity: true,
      fidelityDifferences: [],
      playbackVerified: action === "verify_playback",
      undoAvailable: action === "delete",
      regions: action === "delete" ? [] : [region],
    },
    evidence: [{ source: "Logic MIDI region and event observation", observedAt: timestamp, value: { regionCount: action === "delete" ? 0 : 1 } }],
  });
  const bridge: LogicBridge = {
    ...unusedProjectBridge,
    ...unusedTrackBridge,
    doctor: async () => { throw new Error("unused"); },
    inspectUI: async () => { throw new Error("unused"); },
    transportState: async () => { throw new Error("unused"); },
    setTransportPlaying: async () => { throw new Error("unused"); },
    moveTransportPlayhead: async () => { throw new Error("unused"); },
    locateTransport: async () => { throw new Error("unused"); },
    async midiRegionState(request) { calls.push({ method: "state", request }); return makeResult(request.operationId, "observe"); },
    async createMIDIRegion(request) { calls.push({ method: "create", request }); return makeResult(request.operationId, "create"); },
    renameMIDIRegion: async () => { throw new Error("unused"); },
    moveMIDIRegion: async () => { throw new Error("unused"); },
    resizeMIDIRegion: async () => { throw new Error("unused"); },
    duplicateMIDIRegion: async () => { throw new Error("unused"); },
    splitMIDIRegion: async () => { throw new Error("unused"); },
    async updateMIDINote(request) { calls.push({ method: "update", request }); return makeResult(request.operationId, "update_note"); },
    replaceMIDINotes: async () => { throw new Error("unused"); },
    async deleteMIDIRegion(request) { calls.push({ method: "delete", request }); return makeResult(request.operationId, "delete"); },
    async verifyMIDIRegionPlayback(request) { calls.push({ method: "playback", request }); return makeResult(request.operationId, "verify_playback"); },
  };
  let operation = 0;
  const server = createLogicMcpServer({ bridge, createOperationId: () => `midi-${++operation}` });
  const client = new Client({ name: "midi-client", version: "1.0.0" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  t.after(async () => { await client.close(); await server.close(); });

  const note = { pitch: 60, onset: { ticks: 0, ppq: 960 }, duration: { ticks: 960, ppq: 960 }, velocity: 100, channel: 1 };
  const created = await client.callTool({
    name: "logic_create_midi_region",
    arguments: { trackId: "track-a", name: "Four Bars", position: { ticks: 3840, ppq: 960 }, length: { ticks: 15360, ppq: 960 }, notes: [note], timeoutMs: 1000 },
  });
  assert.equal(created.isError, undefined);
  assert.equal((created.structuredContent as Record<string, unknown>)["exactFidelity"], true);

  await client.callTool({ name: "logic_update_midi_note", arguments: { regionId: "region-a", noteId: "note-a", note, timeoutMs: 1000 } });
  const deniedDelete = await client.callTool({ name: "logic_delete_midi_region", arguments: { regionId: "region-a", timeoutMs: 1000 } });
  assert.equal(deniedDelete.isError, true);
  await client.callTool({ name: "logic_delete_midi_region", arguments: { regionId: "region-a", confirm: true, timeoutMs: 1000 } });
  const playback = await client.callTool({ name: "logic_verify_midi_region_playback", arguments: { regionId: "region-a", timeoutMs: 1000 } });
  assert.equal((playback.structuredContent as Record<string, unknown>)["playbackVerified"], true);

  const resource = await client.readResource({ uri: "logic://midi/regions/state" });
  const content = resource.contents[0];
  assert.ok(content && "text" in content);
  assert.equal(JSON.parse(content.text).state.regions[0].notes[0].channel, 1);
  assert.deepEqual(calls.map(({ method }) => method), ["create", "update", "delete", "playback", "state"]);
});
