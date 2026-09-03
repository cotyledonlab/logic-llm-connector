import { spawn } from "node:child_process";
import { pathToFileURL } from "node:url";

const defaultTimeoutMs = 240_000;

export interface RealLogicMIDIAcceptanceResult {
  code: number | null;
  signal: NodeJS.Signals | null;
  stderr: string;
  stdout: string;
  timedOut: boolean;
}

export interface RealLogicMIDIAcceptanceOptions {
  cwd?: string;
  managedProjectPath: string;
  timeoutMs?: number;
  writeOutput?: (chunk: string) => void;
}

export async function runRealLogicMIDIAcceptance(
  options: RealLogicMIDIAcceptanceOptions,
): Promise<RealLogicMIDIAcceptanceResult> {
  const timeoutMs = options.timeoutMs ?? defaultTimeoutMs;
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs <= 0) {
    throw new Error("MIDI acceptance timeout must be a positive integer");
  }

  const writeOutput = options.writeOutput ?? ((chunk: string) => process.stderr.write(chunk));
  writeOutput(`MIDI_ACCEPTANCE_STAGE process-started timeout-ms=${timeoutMs}\n`);
  const child = spawn(
    "caffeinate",
    [
      "-d",
      "-i",
      "-m",
      "swift",
      "test",
      "--package-path",
      "native/LogicCompanion",
      "--filter",
      "LogicBridgeCoreTests.realLogicMIDIOperationsRoundTripFourBars",
    ],
    {
      cwd: options.cwd ?? process.cwd(),
      detached: true,
      env: {
        ...process.env,
        LOGIC_MANAGED_TEST_PROJECT_PATH: options.managedProjectPath,
        LOGIC_MIDI_ADAPTER_DISCOVERY: "1",
        LOGIC_MIDI_INTEGRATION_TEST: "1",
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );

  let stderr = "";
  let stdout = "";
  let timedOut = false;
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk: string) => {
    stdout += chunk;
    writeOutput(chunk);
  });
  child.stderr.on("data", (chunk: string) => {
    stderr += chunk;
    writeOutput(chunk);
  });

  const terminateGroup = (signal: NodeJS.Signals): void => {
    if (child.pid === undefined) return;
    try {
      process.kill(-child.pid, signal);
    } catch (error) {
      if (!(error instanceof Error && "code" in error && error.code === "ESRCH")) {
        throw error;
      }
    }
  };

  let forceKill: NodeJS.Timeout | undefined;
  const watchdog = setTimeout(() => {
    timedOut = true;
    writeOutput(`MIDI_ACCEPTANCE_STAGE process-timeout timeout-ms=${timeoutMs}\n`);
    terminateGroup("SIGTERM");
    forceKill = setTimeout(() => terminateGroup("SIGKILL"), 2_000);
    forceKill.unref();
  }, timeoutMs);
  watchdog.unref();

  return await new Promise((resolve, reject) => {
    child.once("error", (error) => {
      clearTimeout(watchdog);
      if (forceKill !== undefined) clearTimeout(forceKill);
      reject(error);
    });
    child.once("close", (code, signal) => {
      clearTimeout(watchdog);
      if (forceKill !== undefined) clearTimeout(forceKill);
      writeOutput(
        `MIDI_ACCEPTANCE_STAGE process-exited code=${String(code)} signal=${String(signal)} timed-out=${String(timedOut)}\n`,
      );
      resolve({ code, signal, stderr, stdout, timedOut });
    });
  });
}

const entryPoint = process.argv[1];
if (entryPoint !== undefined && import.meta.url === pathToFileURL(entryPoint).href) {
  const managedProjectPath = process.env["LOGIC_MANAGED_TEST_PROJECT_PATH"];
  if (managedProjectPath === undefined || managedProjectPath.length === 0) {
    throw new Error("set LOGIC_MANAGED_TEST_PROJECT_PATH to the open managed Test Project");
  }
  const configuredTimeout = process.env["LOGIC_MIDI_ACCEPTANCE_TIMEOUT_MS"];
  const result = await runRealLogicMIDIAcceptance({
    managedProjectPath,
    ...(configuredTimeout === undefined ? {} : { timeoutMs: Number(configuredTimeout) }),
  });
  process.exitCode = result.timedOut ? 124 : (result.code ?? 1);
}
