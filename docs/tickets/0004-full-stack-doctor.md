# 0004 — Prove Doctor across the complete stack

Status: Complete
Depends on: 0002, 0003
Commit: `b1644cd`

## Outcome

An MCP stdio client reaches the Swift Companion over a mode-`0600` Unix socket
and receives observations from the installed, running Logic Pro 12.3 process.

## Acceptance criteria

- The TypeScript socket adapter implements the native interface.
- The Swift process routes versioned JSON-RPC messages.
- A real-Logic integration test passes on the target Mac.
- Unit, contract, native, type-check, and build gates pass.
