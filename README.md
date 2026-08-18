# Logic LLM Connector

A local MCP server and macOS companion for verified, programmatic control of
Logic Pro. The project favors semantic music-production operations while using
multiple Logic adapters behind one stable interface.

## Status

Foundation work is in progress. The first supported capability is environment
diagnosis; mutating Logic tools are added only after they pass a real-Logic
integration test.

## Architecture

- `packages/mcp-server`: TypeScript MCP interface and orchestration
- `native/LogicCompanion`: Swift adapter for macOS Accessibility, CoreMIDI,
  and Apple Events
- `schemas`: versioned JSON-RPC contract at the native seam
- `tests`: contract, protocol, and real-Logic acceptance tests

See [docs/architecture.md](docs/architecture.md) for the invariants and test
seams.

## Development

Requires Node.js 22+, Swift 6+, macOS, and Logic Pro for native acceptance
tests.

```sh
npm install
npm test
npm run test:integration
```

Real-Logic tests will always use disposable fixtures and require explicit test
mode. The current integration test is read-only: it launches the Swift
companion, connects over a mode-`0600` Unix socket, and verifies `logic_doctor`
through a real MCP stdio client against the running Logic installation.

## Current capability

`logic_doctor` reports timestamped evidence for:

- macOS version and processor architecture
- Logic Pro installation, version, build, and running state
- Accessibility permission status and remediation

Run `npm run build:native`, launch the companion, then run the MCP server:

```sh
native/LogicCompanion/.build/debug/logic-companion \
  --socket /tmp/logic-llm-connector-$(id -u).sock
npm run build
npm start
```

When using a different path, pass it to the companion and set the same path in
`LOGIC_COMPANION_SOCKET` for the MCP server.
