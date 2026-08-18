import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);
const appPath = fileURLToPath(new URL("../../build/Logic Companion.app", import.meta.url));

test("companion is a signed macOS app with a stable identity", async () => {
  const plistPath = `${appPath}/Contents/Info.plist`;
  const { stdout: identifier } = await execFileAsync("plutil", [
    "-extract",
    "CFBundleIdentifier",
    "raw",
    plistPath,
  ]);
  const { stderr: signature } = await execFileAsync("codesign", [
    "--display",
    "--verbose=4",
    appPath,
  ]);
  const { stdout: requirementOutput, stderr: requirementError } = await execFileAsync("codesign", [
    "-d",
    "-r-",
    "--verbose=4",
    appPath,
  ]);
  const requirement = `${requirementOutput}${requirementError}`;

  assert.equal(identifier.trim(), "dev.cotyledonlab.logic-llm-connector.companion");
  assert.match(signature, /Identifier=dev\.cotyledonlab\.logic-llm-connector\.companion/);
  assert.match(signature, /Authority=Apple Development:/);
  assert.match(signature, /TeamIdentifier=4N63MQVR2B/);
  assert.match(requirement, /anchor apple generic/);
  assert.doesNotMatch(requirement, /designated => cdhash/);
});
