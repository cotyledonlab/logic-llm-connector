import { createConnection } from "node:net";

import type { DoctorResult, LogicBridge } from "./server.js";

export interface UnixSocketLogicBridgeOptions {
  socketPath: string;
  timeoutMs?: number;
}

export class UnixSocketLogicBridge implements LogicBridge {
  readonly #socketPath: string;
  readonly #timeoutMs: number;

  constructor({ socketPath, timeoutMs = 5_000 }: UnixSocketLogicBridgeOptions) {
    this.#socketPath = socketPath;
    this.#timeoutMs = timeoutMs;
  }

  doctor(request: {
    protocolVersion: "1.0.0";
    operationId: string;
  }): Promise<DoctorResult> {
    return new Promise((resolve, reject) => {
      const socket = createConnection(this.#socketPath);
      let buffer = "";
      let settled = false;

      const fail = (error: Error) => {
        if (settled) return;
        settled = true;
        socket.destroy();
        reject(error);
      };

      socket.setEncoding("utf8");
      socket.setTimeout(this.#timeoutMs, () => {
        fail(new Error(`Logic companion timed out after ${this.#timeoutMs}ms`));
      });
      socket.on("error", fail);
      socket.on("connect", () => {
        socket.write(
          `${JSON.stringify({
            jsonrpc: "2.0",
            id: request.operationId,
            method: "logic.doctor",
            params: request,
          })}\n`,
        );
      });
      socket.on("data", (chunk: string) => {
        buffer += chunk;
        const newline = buffer.indexOf("\n");
        if (newline === -1 || settled) return;

        try {
          const response = JSON.parse(buffer.slice(0, newline)) as {
            result?: DoctorResult;
            error?: { code: number; message: string };
          };
          if (response.error) {
            fail(new Error(`Logic companion error ${response.error.code}: ${response.error.message}`));
            return;
          }
          if (!response.result) {
            fail(new Error("Logic companion returned no result"));
            return;
          }
          settled = true;
          socket.end();
          resolve(response.result);
        } catch (error) {
          fail(error instanceof Error ? error : new Error(String(error)));
        }
      });
    });
  }
}
