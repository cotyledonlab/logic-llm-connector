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
  TrackOperationResult,
  LogicTrackType,
  MIDIRegionOperationResult,
  MIDINoteContent,
  MusicalTime,
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

  trackState(request: { protocolVersion: "1.0.0"; operationId: string }): Promise<TrackOperationResult> {
    return this.#request("logic.tracks.state", request);
  }

  createTrack(request: {
    protocolVersion: "1.0.0"; operationId: string;
    type: Exclude<LogicTrackType, "unknown">; name?: string; timeoutMs: number;
  }): Promise<TrackOperationResult> {
    return this.#request("logic.tracks.create", request);
  }

  renameTrack(request: {
    protocolVersion: "1.0.0"; operationId: string; trackId: string; name: string; timeoutMs: number;
  }): Promise<TrackOperationResult> {
    return this.#request("logic.tracks.rename", request);
  }

  selectTrack(request: {
    protocolVersion: "1.0.0"; operationId: string; trackId: string; timeoutMs: number;
  }): Promise<TrackOperationResult> {
    return this.#request("logic.tracks.select", request);
  }

  duplicateTrack(request: {
    protocolVersion: "1.0.0"; operationId: string; trackId: string; name?: string; timeoutMs: number;
  }): Promise<TrackOperationResult> {
    return this.#request("logic.tracks.duplicate", request);
  }

  reorderTrack(request: {
    protocolVersion: "1.0.0"; operationId: string; trackId: string; position: number; timeoutMs: number;
  }): Promise<TrackOperationResult> {
    return this.#request("logic.tracks.reorder", request);
  }

  deleteTrack(request: {
    protocolVersion: "1.0.0"; operationId: string; trackId: string; confirm: boolean; timeoutMs: number;
  }): Promise<TrackOperationResult> {
    return this.#request("logic.tracks.delete", request);
  }

  midiRegionState(request: { protocolVersion: "1.0.0"; operationId: string }): Promise<MIDIRegionOperationResult> {
    return this.#request("logic.midiRegions.state", request);
  }

  createMIDIRegion(request: {
    protocolVersion: "1.0.0"; operationId: string; trackId: string; name: string;
    position: MusicalTime; length: MusicalTime; notes: MIDINoteContent[]; timeoutMs: number;
  }): Promise<MIDIRegionOperationResult> {
    return this.#request("logic.midiRegions.create", request);
  }

  renameMIDIRegion(request: { protocolVersion: "1.0.0"; operationId: string; regionId: string; name: string; timeoutMs: number }): Promise<MIDIRegionOperationResult> {
    return this.#request("logic.midiRegions.rename", request);
  }

  moveMIDIRegion(request: { protocolVersion: "1.0.0"; operationId: string; regionId: string; position: MusicalTime; timeoutMs: number }): Promise<MIDIRegionOperationResult> {
    return this.#request("logic.midiRegions.move", request);
  }

  resizeMIDIRegion(request: { protocolVersion: "1.0.0"; operationId: string; regionId: string; length: MusicalTime; timeoutMs: number }): Promise<MIDIRegionOperationResult> {
    return this.#request("logic.midiRegions.resize", request);
  }

  duplicateMIDIRegion(request: { protocolVersion: "1.0.0"; operationId: string; regionId: string; position: MusicalTime; timeoutMs: number }): Promise<MIDIRegionOperationResult> {
    return this.#request("logic.midiRegions.duplicate", request);
  }

  splitMIDIRegion(request: { protocolVersion: "1.0.0"; operationId: string; regionId: string; position: MusicalTime; timeoutMs: number }): Promise<MIDIRegionOperationResult> {
    return this.#request("logic.midiRegions.split", request);
  }

  updateMIDINote(request: { protocolVersion: "1.0.0"; operationId: string; regionId: string; noteId: string; note: MIDINoteContent; timeoutMs: number }): Promise<MIDIRegionOperationResult> {
    return this.#request("logic.midiRegions.updateNote", request);
  }

  replaceMIDINotes(request: { protocolVersion: "1.0.0"; operationId: string; regionId: string; notes: MIDINoteContent[]; timeoutMs: number }): Promise<MIDIRegionOperationResult> {
    return this.#request("logic.midiRegions.replaceNotes", request);
  }

  deleteMIDIRegion(request: { protocolVersion: "1.0.0"; operationId: string; regionId: string; confirm: boolean; timeoutMs: number }): Promise<MIDIRegionOperationResult> {
    return this.#request("logic.midiRegions.delete", request);
  }

  verifyMIDIRegionPlayback(request: { protocolVersion: "1.0.0"; operationId: string; regionId: string; timeoutMs: number }): Promise<MIDIRegionOperationResult> {
    return this.#request("logic.midiRegions.verifyPlayback", request);
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
