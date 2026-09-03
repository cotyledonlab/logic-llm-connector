import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { rm, stat } from "node:fs/promises";
import { dirname, join } from "node:path";
import test from "node:test";

import { Client } from "@modelcontextprotocol/client";
import { StdioClientTransport } from "@modelcontextprotocol/client/stdio";

import { UnixSocketLogicBridge } from "../../packages/mcp-server/src/unix-socket-bridge.js";
import { runRealLogicMIDIAcceptance } from "../../scripts/run-real-logic-midi-acceptance.js";

const companionPath = join(
  process.cwd(),
  "build/Logic Companion.app/Contents/MacOS/logic-companion",
);
const projectAcceptanceEnabled = process.env["LOGIC_PROJECT_INTEGRATION_TEST"] === "1";
const trackAcceptanceEnabled = process.env["LOGIC_TRACK_INTEGRATION_TEST"] === "1";
const midiAcceptanceEnabled = process.env["LOGIC_MIDI_INTEGRATION_TEST"] === "1";
const isolatedAcceptanceEnabled = projectAcceptanceEnabled || trackAcceptanceEnabled || midiAcceptanceEnabled;

async function waitForSocket(path: string): Promise<void> {
  const deadline = Date.now() + 5_000;
  while (Date.now() < deadline) {
    try {
      await stat(path);
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
  }
  throw new Error(`Companion did not create ${path}`);
}

async function waitForMackieAcceptance(
  bridge: UnixSocketLogicBridge,
): Promise<Awaited<ReturnType<UnixSocketLogicBridge["doctor"]>>> {
  const deadline = Date.now() + 5_000;
  let result: Awaited<ReturnType<UnixSocketLogicBridge["doctor"]>> | undefined;
  while (Date.now() < deadline) {
    result = await bridge.doctor({
      protocolVersion: "1.0.0",
      operationId: "real-logic-doctor",
    });
    const checks = result.data.checks;
    if (
      checks.find((check) => check.id === "logic.control_surface.mackie")?.status ===
        "passed" &&
      checks.find((check) => check.id === "midi.mackie_feedback")?.status ===
        "passed"
    ) {
      return result;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  if (result) return result;
  throw new Error("Doctor did not return a result");
}

test("TypeScript diagnoses the running Logic instance through the native socket", {
  skip: isolatedAcceptanceEnabled ? "isolated project or track acceptance requested" : false,
}, async (t) => {
  const socketPath = `/tmp/logic-llm-connector-${process.pid}.sock`;
  await rm(socketPath, { force: true });

  const companion = spawn(companionPath, ["--socket", socketPath], {
    env: { ...process.env, LOGIC_ENABLE_DIAGNOSTICS: "1" },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stderr = "";
  companion.stderr.setEncoding("utf8");
  companion.stderr.on("data", (chunk) => {
    stderr += chunk;
  });
  t.after(async () => {
    companion.kill("SIGTERM");
    await rm(socketPath, { force: true });
  });

  await waitForSocket(socketPath);
  const bridge = new UnixSocketLogicBridge({ socketPath, timeoutMs: 2_000 });
  const result = await waitForMackieAcceptance(bridge);

  assert.equal(stderr, "");
  assert.equal(result.operationId, "real-logic-doctor");
  assert.equal(result.status, "succeeded");
  const logic = result.data.checks.find((check) => check.id === "logic.application");
  assert.equal(logic?.status, "passed");
  assert.match(logic?.summary ?? "", /Logic Pro 12\.3 is installed and running/);
  const midi = result.data.checks.find(
    (check) => check.id === "midi.virtual_endpoints",
  );
  assert.equal(midi?.status, "passed");
  assert.equal(
    midi?.summary,
    "CoreMIDI MIDI 1.0 source and destination are available",
  );
  assert.match(JSON.stringify(midi?.evidence), /Logic LLM Connector Out/);
  assert.match(JSON.stringify(midi?.evidence), /Logic LLM Connector In/);
  const accessibility = result.data.checks.find(
    (check) => check.id === "permission.accessibility",
  );
  assert.equal(accessibility?.status, "passed");
  const mackie = result.data.checks.find(
    (check) => check.id === "logic.control_surface.mackie",
  );
  assert.equal(mackie?.status, "passed", JSON.stringify(mackie));
  assert.equal(
    mackie?.summary,
    "Mackie Control is assigned to both Logic LLM Connector MIDI ports",
  );
  const mackieEvidence = JSON.stringify(mackie?.evidence);
  assert.match(mackieEvidence, /"state":"configured"/);
  assert.match(mackieEvidence, /"model":"Mackie Control"/);
  assert.match(mackieEvidence, /"inputPort":"Logic LLM Connector Out"/);
  assert.match(mackieEvidence, /"outputPort":"Logic LLM Connector In"/);
  const feedback = result.data.checks.find(
    (check) => check.id === "midi.mackie_feedback",
  );
  assert.equal(feedback?.status, "passed", JSON.stringify(feedback));
  assert.equal(
    feedback?.summary,
    "Logic sent Mackie-compatible feedback to the Companion",
  );
  assert.match(JSON.stringify(feedback?.evidence), /"packetCount":[1-9][0-9]*/);

  const mcpTransport = new StdioClientTransport({
    command: join(process.cwd(), "node_modules/.bin/tsx"),
    args: [join(process.cwd(), "packages/mcp-server/src/main.ts")],
    env: {
      LOGIC_COMPANION_SOCKET: socketPath,
      PATH: process.env.PATH ?? "",
    },
    cwd: process.cwd(),
    stderr: "pipe",
  });
  const client = new Client({ name: "integration-client", version: "1.0.0" });
  t.after(async () => client.close());
  await client.connect(mcpTransport);
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
  ]);
  const mcpResult = await client.callTool({ name: "logic_doctor", arguments: {} });
  assert.equal(mcpResult.isError, undefined);
  const structuredContent = mcpResult.structuredContent as
    | Record<string, unknown>
    | undefined;
  assert.equal(structuredContent?.["status"], "succeeded");
  assert.match(JSON.stringify(structuredContent), /Logic Pro 12\.3/);

  const initialTransport = await bridge.transportState({
    protocolVersion: "1.0.0",
    operationId: "transport-initial",
  });
  assert.notEqual(
    initialTransport.data.playing,
    "unknown",
    JSON.stringify(initialTransport),
  );
  const restorePlaying = initialTransport.data.playing === "playing";
  assert.notEqual(
    initialTransport.data.cycle,
    "unknown",
    "real-Logic transport acceptance requires observable Cycle feedback",
  );
  let transportFailure: unknown;
  try {
    const stopped = await client.callTool({
      name: "logic_stop",
      arguments: { timeoutMs: 1500 },
    });
    assert.equal(stopped.isError, undefined, JSON.stringify(stopped.content));
    assert.equal(
      (stopped.structuredContent as Record<string, unknown>)?.["status"],
      "succeeded",
    );

    if (process.env["LOGIC_LOCATION_INTEGRATION_TEST"] === "1") {
      const baseline = await bridge.locateTransport({
        protocolVersion: "1.0.0",
        operationId: "location-baseline",
        target: "project_start",
        timeoutMs: 1500,
      });
      assert.equal(baseline.status, "succeeded", JSON.stringify(baseline));
      const locationStart = baseline.data.position.display;
      assert.ok(locationStart, JSON.stringify(baseline));
      try {
        const moved = await bridge.moveTransportPlayhead({
          protocolVersion: "1.0.0",
          operationId: "location-forward",
          direction: "forward",
          steps: 10,
          timeoutMs: 1500,
        });
        const locationCurrent = moved.data.position.display;
        assert.equal(moved.status, "succeeded", JSON.stringify(moved));
        assert.equal(moved.reliability, "verified_deterministic");
        assert.ok(
          locationStart && locationCurrent && locationCurrent > locationStart,
          JSON.stringify(moved),
        );

      } finally {
        const restored = await bridge.locateTransport({
          protocolVersion: "1.0.0",
          operationId: "location-restore",
          target: "project_start",
          timeoutMs: 1500,
        });
        assert.equal(restored.status, "succeeded", JSON.stringify(restored));
        assert.equal(
          restored.data.position.display,
          locationStart,
          "real-Logic playhead restoration failed",
        );
      }
    }

    const finder = spawnSync("open", ["-a", "Finder"]);
    assert.equal(finder.status, 0, finder.stderr?.toString());
    await new Promise((resolve) => setTimeout(resolve, 250));

    const played = await client.callTool({
      name: "logic_play",
      arguments: { timeoutMs: 1500 },
    });
    assert.equal(played.isError, undefined, JSON.stringify(played.content));
    const playedContent = played.structuredContent as Record<string, unknown>;
    assert.equal(playedContent?.["status"], "succeeded");
    assert.equal(playedContent?.["reliability"], "verified_deterministic");
    assert.equal(
      (playedContent?.["state"] as Record<string, unknown>)?.["playing"],
      "playing",
    );
    assert.match(JSON.stringify(playedContent?.["evidence"]), /Mackie Control feedback/);

    const transportResource = await client.readResource({
      uri: "logic://transport/state",
    });
    const transportContent = transportResource.contents[0];
    assert.ok(transportContent && "text" in transportContent);
    assert.equal(JSON.parse(transportContent.text).state.playing, "playing");
    await new Promise((resolve) => setTimeout(resolve, 250));

    const stoppedAgain = await client.callTool({
      name: "logic_stop",
      arguments: { timeoutMs: 1500 },
    });
    assert.equal(stoppedAgain.isError, undefined, JSON.stringify(stoppedAgain.content));
    assert.equal(
      (stoppedAgain.structuredContent as Record<string, unknown>)?.["status"],
      "succeeded",
      JSON.stringify(stoppedAgain.structuredContent),
    );
    assert.equal(
      ((stoppedAgain.structuredContent as Record<string, unknown>)?.["state"] as
        Record<string, unknown>)?.["playing"],
      "stopped",
    );

  } catch (error) {
    transportFailure = error;
  } finally {
    const restored = await bridge.setTransportPlaying({
      protocolVersion: "1.0.0",
      operationId: "transport-restore",
      playing: restorePlaying,
      timeoutMs: 1500,
    });
    if (transportFailure === undefined) {
      assert.equal(restored.status, "succeeded", JSON.stringify(restored));
    }
  }
  if (transportFailure !== undefined) throw transportFailure;
  await client.close();

  const diagnosticTransport = new StdioClientTransport({
    command: join(process.cwd(), "node_modules/.bin/tsx"),
    args: [join(process.cwd(), "packages/mcp-server/src/main.ts")],
    env: {
      LOGIC_COMPANION_SOCKET: socketPath,
      LOGIC_ENABLE_DIAGNOSTICS: "1",
      PATH: process.env.PATH ?? "",
    },
    cwd: process.cwd(),
    stderr: "pipe",
  });
  const diagnosticClient = new Client({
    name: "diagnostic-integration-client",
    version: "1.0.0",
  });
  t.after(async () => diagnosticClient.close());
  await diagnosticClient.connect(diagnosticTransport);
  assert.deepEqual((await diagnosticClient.listTools()).tools.map((tool) => tool.name), [
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
  const inspection = await diagnosticClient.callTool({
    name: "logic_inspect_ui",
    arguments: { maxDepth: 2, maxNodes: 100 },
  });
  assert.equal(inspection.isError, undefined, JSON.stringify(inspection.content));
  assert.ok(inspection.structuredContent, JSON.stringify(inspection.content));
  const inspectionContent = inspection.structuredContent as Record<string, unknown>;
  const nodes = inspectionContent["nodes"] as Array<Record<string, unknown>>;
  assert.equal(inspectionContent["status"], "succeeded");
  assert.ok(nodes.length > 0 && nodes.length <= 100);
  assert.equal(nodes[0]?.["role"], "AXApplication");
  assert.equal(nodes[0]?.["title"], undefined);
  assert.equal(nodes[0]?.["value"], undefined);
  assert.equal(nodes[0]?.["description"], undefined);
});

test("MCP safely owns a copied Test Project through lifecycle and optional track acceptance", {
  skip: isolatedAcceptanceEnabled ? false : "set a project, track, or MIDI integration test flag",
  timeout: 300_000,
}, async (t) => {
  const fixturePath = process.env["LOGIC_TEST_PROJECT_FIXTURE"];
  assert.ok(fixturePath, "set LOGIC_TEST_PROJECT_FIXTURE to a saved .logicx fixture");
  const socketPath = `/tmp/logic-llm-connector-project-${process.pid}.sock`;
  await rm(socketPath, { force: true });
  const companion = spawn(companionPath, ["--socket", socketPath], {
    env: process.env,
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stderr = "";
  companion.stderr.setEncoding("utf8");
  companion.stderr.on("data", (chunk) => { stderr += chunk; });
  t.after(async () => {
    companion.kill("SIGTERM");
    await rm(socketPath, { force: true });
  });
  await waitForSocket(socketPath);
  // Logic processes the freshly recreated virtual MIDI endpoints asynchronously.
  // Let that startup work settle before dispatching the first document command.
  await new Promise((resolve) => setTimeout(resolve, 1_000));

  const nativeBridge = new UnixSocketLogicBridge({ socketPath, timeoutMs: 65_000 });
  const initial = await nativeBridge.projectState({
    protocolVersion: "1.0.0",
    operationId: "project-precondition",
  });
  assert.equal(
    initial.data.project,
    undefined,
    `close the current Logic document before project acceptance: ${JSON.stringify(initial.data.project)}`,
  );

  const transport = new StdioClientTransport({
    command: join(process.cwd(), "node_modules/.bin/tsx"),
    args: [join(process.cwd(), "packages/mcp-server/src/main.ts")],
    env: {
      LOGIC_COMPANION_SOCKET: socketPath,
      PATH: process.env.PATH ?? "",
    },
    cwd: process.cwd(),
    stderr: "pipe",
  });
  const client = new Client({ name: "project-acceptance-client", version: "1.0.0" });
  await client.connect(transport);
  t.after(async () => client.close());

  const call = async (name: string, args: Record<string, unknown>) => {
    const result = await client.callTool({ name, arguments: args });
    assert.equal(result.isError, undefined, JSON.stringify(result.content));
    return result.structuredContent as Record<string, unknown>;
  };
  const cleanup = async () => {
    const result = await nativeBridge.cleanupTestProject({
      protocolVersion: "1.0.0",
      operationId: `cleanup-${randomUUID()}`,
      timeoutMs: 10_000,
    });
    return { ...result, ...result.data } as Record<string, unknown>;
  };

  let managedPath: string | undefined;
  try {
    const opened = await call("logic_open_test_project", {
      fixturePath,
      timeoutMs: 30_000,
    });
    assert.equal(opened["status"], "succeeded", JSON.stringify(opened));
    assert.equal(opened["policyContext"], true);
    managedPath = opened["managedProjectPath"] as string;
    assert.notEqual(managedPath, fixturePath, "Logic must open the copied fixture, never the source");

    const duplicateOpen = await call("logic_open_test_project", {
      fixturePath,
      timeoutMs: 30_000,
    });
    assert.equal(duplicateOpen["status"], "failed", JSON.stringify(duplicateOpen));
    assert.equal(duplicateOpen["failure"], "user_project_open");

    const saved = await call("logic_save_test_project", {
      confirm: true,
      timeoutMs: 30_000,
    });
    assert.equal(saved["status"], "succeeded", JSON.stringify(saved));
    assert.equal((saved["project"] as Record<string, unknown>)["modified"], false);

    const closed = await call("logic_close_test_project", { timeoutMs: 30_000 });
    assert.equal(closed["status"], "succeeded", JSON.stringify(closed));
    assert.equal(closed["project"], undefined);

    const reopened = await call("logic_reopen_test_project", { timeoutMs: 30_000 });
    assert.equal(reopened["status"], "succeeded", JSON.stringify(reopened));
    assert.equal((reopened["project"] as Record<string, unknown>)["path"], managedPath);

    if (trackAcceptanceEnabled) {
      const trackAcceptance = spawnSync(
        "swift",
        [
          "test",
          "--package-path",
          "native/LogicCompanion",
          "--filter",
          "LogicBridgeCoreTests.realLogicTrackOperationsPreserveIdentityInsidePackagedCopy",
        ],
        {
          cwd: process.cwd(),
          env: {
            ...process.env,
            LOGIC_TRACK_INTEGRATION_TEST: "1",
            LOGIC_MANAGED_TEST_PROJECT_PATH: managedPath,
          },
          encoding: "utf8",
          timeout: 120_000,
        },
      );
      assert.equal(
        trackAcceptance.status,
        0,
        `real-Logic track acceptance failed:\n${trackAcceptance.stdout}\n${trackAcceptance.stderr}`,
      );
      await new Promise((resolve) => setTimeout(resolve, 1_000));
      const postTrackProject = await nativeBridge.projectState({
        protocolVersion: "1.0.0",
        operationId: "project-post-track-acceptance",
      });
      assert.equal(postTrackProject.status, "succeeded", JSON.stringify(postTrackProject));
      assert.equal(postTrackProject.data.project?.path, managedPath);
      await new Promise((resolve) => setTimeout(resolve, 2_000));
      const savedAfterTracks = await call("logic_save_test_project", { confirm: true, timeoutMs: 30_000 });
      assert.equal(savedAfterTracks["status"], "succeeded", JSON.stringify(savedAfterTracks));
      await new Promise((resolve) => setTimeout(resolve, 1_000));
      let settledProject = await nativeBridge.projectState({
        protocolVersion: "1.0.0",
        operationId: "project-post-track-save",
      });
      if (settledProject.data.project?.modified) {
        const resavedAfterTracks = await call("logic_save_test_project", { confirm: true, timeoutMs: 30_000 });
        assert.equal(resavedAfterTracks["status"], "succeeded", JSON.stringify(resavedAfterTracks));
        await new Promise((resolve) => setTimeout(resolve, 1_000));
        settledProject = await nativeBridge.projectState({
          protocolVersion: "1.0.0",
          operationId: "project-post-track-resave",
        });
      }
      assert.equal(settledProject.data.project?.modified, false, JSON.stringify(settledProject));
    }

    if (midiAcceptanceEnabled) {
      const midiAcceptance = await runRealLogicMIDIAcceptance({
        managedProjectPath: managedPath,
        timeoutMs: 240_000,
      });
      assert.equal(
        midiAcceptance.timedOut ? 124 : midiAcceptance.code,
        0,
        `real-Logic MIDI acceptance failed:\n${midiAcceptance.stdout}\n${midiAcceptance.stderr}`,
      );
      process.stderr.write("MIDI_ACCEPTANCE_STAGE native-pass\n");
      await new Promise((resolve) => setTimeout(resolve, 1_000));
      const postMIDIProject = await nativeBridge.projectState({
        protocolVersion: "1.0.0",
        operationId: "project-post-midi-acceptance",
      });
      assert.equal(postMIDIProject.status, "succeeded", JSON.stringify(postMIDIProject));
      assert.equal(postMIDIProject.data.project?.path, managedPath);
      process.stderr.write("MIDI_ACCEPTANCE_STAGE project-observed\n");
      const savedAfterMIDI = await call("logic_save_test_project", { confirm: true, timeoutMs: 30_000 });
      assert.equal(savedAfterMIDI["status"], "succeeded", JSON.stringify(savedAfterMIDI));
      process.stderr.write("MIDI_ACCEPTANCE_STAGE project-saved\n");
      const closedAfterMIDI = await call("logic_close_test_project", { timeoutMs: 10_000 });
      assert.equal(closedAfterMIDI["status"], "succeeded", JSON.stringify(closedAfterMIDI));
      process.stderr.write("MIDI_ACCEPTANCE_STAGE project-closed\n");
      const closedMIDIState = await nativeBridge.projectState({
        protocolVersion: "1.0.0",
        operationId: "project-post-midi-close",
      });
      assert.equal(closedMIDIState.data.project, undefined, JSON.stringify(closedMIDIState));
      await rm(dirname(managedPath), { recursive: true });
    }
  } finally {
    if (managedPath) {
      await new Promise((resolve) => setTimeout(resolve, 1_000));
      const cleaned = await cleanup();
      assert.equal(cleaned["status"], "succeeded", JSON.stringify(cleaned));
      assert.equal(cleaned["cleanupPerformed"], true);
    }
  }

  const afterSuccess = await nativeBridge.projectState({
    protocolVersion: "1.0.0",
    operationId: "project-after-success",
  });
  assert.equal(afterSuccess.data.project, undefined);
  assert.equal(afterSuccess.data.managedProjectPath, undefined);

  let injectedFailureObserved = false;
  try {
    const opened = await call("logic_open_test_project", {
      fixturePath,
      timeoutMs: 30_000,
    });
    assert.equal(opened["status"], "succeeded", JSON.stringify(opened));
    throw new Error("injected test-body failure");
  } catch (error) {
    assert.match(String(error), /injected test-body failure/);
    injectedFailureObserved = true;
  } finally {
    const cleaned = await cleanup();
    assert.equal(cleaned["status"], "succeeded", JSON.stringify(cleaned));
  }
  assert.equal(injectedFailureObserved, true);
  const afterFailure = await nativeBridge.projectState({
    protocolVersion: "1.0.0",
    operationId: "project-after-failure",
  });
  assert.equal(afterFailure.data.project, undefined);
  assert.equal(afterFailure.data.managedProjectPath, undefined);
  assert.equal(stderr, "");
});
