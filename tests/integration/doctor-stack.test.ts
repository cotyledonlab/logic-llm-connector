import assert from "node:assert/strict";
import { spawn } from "node:child_process";
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
  const bridge = new UnixSocketLogicBridge({ socketPath, timeoutMs: 2_000 });
  const result = await bridge.doctor({
    protocolVersion: "1.0.0",
    operationId: "real-logic-doctor",
  });

  assert.equal(stderr, "");
  assert.equal(result.operationId, "real-logic-doctor");
  assert.equal(result.status, "succeeded");
  const logic = result.data.checks.find((check) => check.id === "logic.application");
  assert.equal(logic?.status, "passed");
  assert.match(logic?.summary ?? "", /Logic Pro 12\.3 is installed and running/);

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
  await client.connect(mcpTransport);
  assert.deepEqual((await client.listTools()).tools.map((tool) => tool.name), [
    "logic_doctor",
  ]);
  const mcpResult = await client.callTool({ name: "logic_doctor", arguments: {} });
  assert.equal(mcpResult.isError, undefined);
  const structuredContent = mcpResult.structuredContent as
    | Record<string, unknown>
    | undefined;
  assert.equal(structuredContent?.["status"], "succeeded");
  assert.match(JSON.stringify(structuredContent), /Logic Pro 12\.3/);
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
