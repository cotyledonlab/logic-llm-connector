import { serveStdio } from "@modelcontextprotocol/server/stdio";

import { createLogicMcpServer } from "./server.js";
import { UnixSocketLogicBridge } from "./unix-socket-bridge.js";

const socketPath =
  process.env.LOGIC_COMPANION_SOCKET ??
  `/tmp/logic-llm-connector-${process.getuid?.() ?? process.pid}.sock`;
const diagnosticsEnabled = process.env.LOGIC_ENABLE_DIAGNOSTICS === "1";

serveStdio(
  () =>
    createLogicMcpServer({
      bridge: new UnixSocketLogicBridge({ socketPath }),
      diagnosticsEnabled,
    }),
  {
    onerror(error) {
      process.stderr.write(`logic-llm-connector: ${error.message}\n`);
    },
  },
);
