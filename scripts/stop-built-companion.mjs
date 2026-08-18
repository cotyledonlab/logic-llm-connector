import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const companionPath = `${process.cwd()}/build/Logic Companion.app/Contents/MacOS/logic-companion`;
const escapedPath = companionPath.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

let stdout;
try {
  ({ stdout } = await execFileAsync("pgrep", ["-f", `^${escapedPath}( |$)`]));
} catch (error) {
  if (error && typeof error === "object" && "code" in error && error.code === 1) {
    process.exit(0);
  }
  throw error;
}

const processIds = stdout
  .trim()
  .split(/\s+/)
  .filter(Boolean)
  .map(Number)
  .filter(Number.isInteger);

for (const processId of processIds) {
  process.kill(processId, "SIGTERM");
}

const deadline = Date.now() + 5_000;
for (const processId of processIds) {
  while (Date.now() < deadline) {
    try {
      process.kill(processId, 0);
      await new Promise((resolve) => setTimeout(resolve, 25));
    } catch (error) {
      if (error && typeof error === "object" && "code" in error && error.code === "ESRCH") {
        break;
      }
      throw error;
    }
  }
  try {
    process.kill(processId, 0);
    throw new Error(`Built Logic Companion process ${processId} did not terminate`);
  } catch (error) {
    if (!(error && typeof error === "object" && "code" in error && error.code === "ESRCH")) {
      throw error;
    }
  }
}
