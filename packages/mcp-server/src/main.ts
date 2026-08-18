import { serveStdio } from "@modelcontextprotocol/server/stdio";

import { createLogicMcpServer } from "./server.js";
import { UnixSocketLogicBridge } from "./unix-socket-bridge.js";

const socketPath =
  process.env.LOGIC_COMPANION_SOCKET ??
  `/tmp/logic-llm-connector-${process.getuid?.() ?? process.pid}.sock`;

serveStdio(
  () =>
    createLogicMcpServer({
      bridge: new UnixSocketLogicBridge({ socketPath }),
    }),
  {
    onerror(error) {
      process.stderr.write(`logic-llm-connector: ${error.message}\n`);
    },
  },
);
