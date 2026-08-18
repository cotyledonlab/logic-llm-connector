import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const schemaUrl = new URL("../../schemas/logic-bridge.schema.json", import.meta.url);

async function validatorFor(definition) {
  const schema = JSON.parse(await readFile(schemaUrl, "utf8"));
  const ajv = new Ajv2020({ allErrors: true, strict: true });
  addFormats(ajv);
  ajv.addSchema(schema);
  return ajv.getSchema(`${schema.$id}#/$defs/${definition}`);
}

test("doctor request is a versioned JSON-RPC request", async () => {
  const validate = await validatorFor("request");
  const request = {
    jsonrpc: "2.0",
    id: "doctor-1",
    method: "logic.doctor",
    params: { protocolVersion: "1.0.0", operationId: "doctor-1" }
  };

  assert.equal(validate(request), true, JSON.stringify(validate.errors));
});

test("doctor request requires an operation ID", async () => {
  const validate = await validatorFor("request");
  const request = {
    jsonrpc: "2.0",
    id: "doctor-1",
    method: "logic.doctor",
    params: { protocolVersion: "1.0.0" }
  };

  assert.equal(validate(request), false);
});

test("doctor result preserves evidence and unknown state", async () => {
  const validate = await validatorFor("response");
  const response = {
    jsonrpc: "2.0",
    id: "doctor-1",
    result: {
      protocolVersion: "1.0.0",
      operationId: "doctor-1",
      status: "succeeded",
      reliability: "verified_deterministic",
      startedAt: "2026-08-18T10:00:00Z",
      finishedAt: "2026-08-18T10:00:00Z",
      data: {
        checks: [
          {
            id: "logic.project",
            status: "unknown",
            summary: "No observable front project",
            evidence: []
          }
        ]
      },
      evidence: [
        {
          source: "workspace",
          observedAt: "2026-08-18T10:00:00Z",
          value: "Logic Pro"
        }
      ]
    }
  };

  assert.equal(validate(response), true, JSON.stringify(validate.errors));
});

test("a successful result cannot omit verification evidence", async () => {
  const validate = await validatorFor("response");
  const response = {
    jsonrpc: "2.0",
    id: 1,
    result: {
      protocolVersion: "1.0.0",
      operationId: "doctor-1",
      status: "succeeded",
      reliability: "verified_deterministic",
      startedAt: "2026-08-18T10:00:00Z",
      finishedAt: "2026-08-18T10:00:00Z",
      data: { checks: [] },
      evidence: []
    }
  };

  assert.equal(validate(response), false);
});

test("UI inspection is bounded and excludes UI text", async () => {
  const validateRequest = await validatorFor("request");
  const validateResponse = await validatorFor("response");
  const request = {
    jsonrpc: "2.0",
    id: "inspect-1",
    method: "logic.inspectUI",
    params: {
      protocolVersion: "1.0.0",
      operationId: "inspect-1",
      maxDepth: 3,
      maxNodes: 200
    }
  };
  const response = {
    jsonrpc: "2.0",
    id: "inspect-1",
    result: {
      protocolVersion: "1.0.0",
      operationId: "inspect-1",
      status: "succeeded",
      reliability: "verified_deterministic",
      startedAt: "2026-08-18T10:00:00Z",
      finishedAt: "2026-08-18T10:00:00Z",
      data: {
        application: { bundleIdentifier: "com.apple.logic10", pid: 42 },
        capturedAt: "2026-08-18T10:00:00Z",
        limits: { maxDepth: 3, maxNodes: 200 },
        truncated: false,
        nodes: [
          {
            id: "node-0",
            parentId: null,
            role: "AXApplication",
            subrole: null,
            identifier: null,
            enabled: true,
            focused: false,
            childCount: 1
          }
        ]
      },
      evidence: [
        {
          source: "AXUIElement",
          observedAt: "2026-08-18T10:00:00Z",
          value: { nodeCount: 1 }
        }
      ]
    }
  };

  assert.equal(validateRequest(request), true, JSON.stringify(validateRequest.errors));
  assert.equal(validateResponse(response), true, JSON.stringify(validateResponse.errors));
  response.result.data.nodes[0].title = "secret project title";
  assert.equal(validateResponse(response), false);
});
