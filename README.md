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
```

Real-Logic tests will always use disposable fixtures and require explicit test
mode.
