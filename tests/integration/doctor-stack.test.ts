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
  t.after(async () => client.close());
  await client.connect(mcpTransport);
  const mcpResult = await client.callTool({ name: "logic_doctor", arguments: {} });
  assert.equal(mcpResult.isError, undefined);
  const structuredContent = mcpResult.structuredContent as
    | Record<string, unknown>
    | undefined;
  assert.equal(structuredContent?.["status"], "succeeded");
  assert.match(JSON.stringify(structuredContent), /Logic Pro 12\.3/);
});
