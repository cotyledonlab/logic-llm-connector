import { createConnection } from "node:net";

import type {
  AXInspectionResult,
  DoctorResult,
  LogicBridge,
  TransportOperationResult,
  TransportLocationOperationResult,
  TransportLocateOperationResult,
  TransportStateResult,
  ProjectLifecycleResult,
} from "./server.js";

export interface UnixSocketLogicBridgeOptions {
  socketPath: string;
  timeoutMs?: number;
}

export class UnixSocketLogicBridge implements LogicBridge {
  readonly #socketPath: string;
  readonly #timeoutMs: number;

  constructor({ socketPath, timeoutMs = 35_000 }: UnixSocketLogicBridgeOptions) {
    this.#socketPath = socketPath;
    this.#timeoutMs = timeoutMs;
  }

  doctor(request: {
    protocolVersion: "1.0.0";
    operationId: string;
  }): Promise<DoctorResult> {
    return this.#request("logic.doctor", request);
  }

  inspectUI(request: {
    protocolVersion: "1.0.0";
    operationId: string;
    maxDepth: number;
    maxNodes: number;
  }): Promise<AXInspectionResult> {
    return this.#request("logic.inspectUI", request);
  }

  transportState(request: {
    protocolVersion: "1.0.0";
    operationId: string;
  }): Promise<TransportStateResult> {
    return this.#request("logic.transport.state", request);
  }

  setTransportPlaying(request: {
    protocolVersion: "1.0.0";
    operationId: string;
    playing: boolean;
    timeoutMs: number;
  }): Promise<TransportOperationResult> {
    return this.#request("logic.transport.setPlaying", request);
  }

  moveTransportPlayhead(request: {
    protocolVersion: "1.0.0";
    operationId: string;
    direction: "backward" | "forward";
    steps: number;
    timeoutMs: number;
  }): Promise<TransportLocationOperationResult> {
    return this.#request("logic.transport.movePlayhead", request);
  }

  locateTransport(request: {
    protocolVersion: "1.0.0";
    operationId: string;
    target: "project_start";
    timeoutMs: number;
  }): Promise<TransportLocateOperationResult> {
    return this.#request("logic.transport.locate", request);
  }

  projectState(request: {
    protocolVersion: "1.0.0";
    operationId: string;
  }): Promise<ProjectLifecycleResult> {
    return this.#request("logic.project.state", request);
  }

  openTestProject(request: {
    protocolVersion: "1.0.0";
    operationId: string;
    fixturePath: string;
    timeoutMs: number;
  }): Promise<ProjectLifecycleResult> {
    return this.#request("logic.project.openFixture", request);
  }

  saveTestProject(request: {
    protocolVersion: "1.0.0";
    operationId: string;
    timeoutMs: number;
  }): Promise<ProjectLifecycleResult> {
    return this.#request("logic.project.save", request);
  }

  closeTestProject(request: {
    protocolVersion: "1.0.0";
    operationId: string;
    timeoutMs: number;
  }): Promise<ProjectLifecycleResult> {
    return this.#request("logic.project.close", request);
  }

  reopenTestProject(request: {
    protocolVersion: "1.0.0";
    operationId: string;
    timeoutMs: number;
  }): Promise<ProjectLifecycleResult> {
    return this.#request("logic.project.reopen", request);
  }

  cleanupTestProject(request: {
    protocolVersion: "1.0.0";
    operationId: string;
    timeoutMs: number;
  }): Promise<ProjectLifecycleResult> {
    return this.#request("logic.project.cleanup", request);
  }

  #request<Result>(method: string, params: object): Promise<Result> {
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
            id: "operationId" in params ? params.operationId : "bridge-request",
            method,
            params,
          })}\n`,
        );
      });
      socket.on("data", (chunk: string) => {
        buffer += chunk;
        const newline = buffer.indexOf("\n");
        if (newline === -1 || settled) return;

        try {
          const response = JSON.parse(buffer.slice(0, newline)) as {
            result?: Result;
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
