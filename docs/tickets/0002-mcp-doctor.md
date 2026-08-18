# 0002 — Expose Doctor through MCP

Status: Complete
Depends on: 0001
Commit: `773b963`

## Outcome

An MCP client can discover and invoke the read-only `logic_doctor` tool through
the TypeScript module.

## Acceptance criteria

- The tool has semantic input/output schemas and read-only annotations.
- Operation IDs cross the native seam.
- A real MCP client test verifies discovery and structured output.
- TypeScript type checking passes.
