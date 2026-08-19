import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { rm, stat } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";

import { Client } from "@modelcontextprotocol/client";
import { StdioClientTransport } from "@modelcontextprotocol/client/stdio";

import { UnixSocketLogicBridge } from "../../packages/mcp-server/src/unix-socket-bridge.js";

const companionPath = join(
  process.cwd(),
  "build/Logic Companion.app/Contents/MacOS/logic-companion",
);

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

test("TypeScript diagnoses the running Logic instance through the native socket", async (t) => {
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
  const activatedLogic = spawnSync("open", ["-a", "Logic Pro"]);
  assert.equal(activatedLogic.status, 0, activatedLogic.stderr?.toString());
  await new Promise((resolve) => setTimeout(resolve, 250));
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

    let locationStart: string | null = null;
    let locationCurrent: string | null = null;
    try {
      const moved = await bridge.moveTransportPlayhead({
        protocolVersion: "1.0.0",
        operationId: "location-forward",
        direction: "forward",
        steps: 10,
        timeoutMs: 1500,
      });
      locationStart = moved.data.initialPosition.display;
      locationCurrent = moved.data.position.display;
      assert.equal(moved.status, "succeeded", JSON.stringify(moved));
      assert.equal(moved.reliability, "verified_deterministic");
      assert.ok(
        locationStart && locationCurrent && locationCurrent > locationStart,
        JSON.stringify(moved),
      );

      const restored = await bridge.moveTransportPlayhead({
        protocolVersion: "1.0.0",
        operationId: "location-backward",
        direction: "backward",
        steps: 10,
        timeoutMs: 1500,
      });
      locationCurrent = restored.data.position.display;
      assert.equal(restored.status, "succeeded", JSON.stringify(restored));
      assert.equal(locationCurrent, locationStart, JSON.stringify(restored));
    } finally {
      for (
        let attempt = 0;
        locationStart && locationCurrent && locationCurrent !== locationStart && attempt < 8;
        attempt += 1
      ) {
        const recovery = await bridge.moveTransportPlayhead({
          protocolVersion: "1.0.0",
          operationId: `location-recovery-${attempt}`,
          direction: locationCurrent < locationStart ? "forward" : "backward",
          steps: 1,
          timeoutMs: 1500,
        });
        locationCurrent = recovery.data.position.display;
      }
      assert.equal(locationCurrent, locationStart, "real-Logic playhead restoration failed");
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
