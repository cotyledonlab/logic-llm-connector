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
seams. [SPEC.md](SPEC.md) is the accepted product and technical specification;
[docs/tickets](docs/tickets/README.md) is the ordered delivery plan and status
source.

## Development

Requires Node.js 22+, Swift 6+, macOS, and Logic Pro for native acceptance
tests.

```sh
npm install
npm test
npm run test:package
npm run test:integration
```

Real-Logic tests will always use disposable fixtures and require explicit test
mode. The current integration tests are read-only: they launch the Swift
Companion, connect over a mode-`0600` Unix socket, verify `logic_doctor` through
a real MCP stdio client, inspect a bounded text-free Accessibility snapshot,
and verify focus-loss and emergency-stop safety against the running Logic
installation.

## Current capability

`logic_doctor` reports timestamped evidence for:

- macOS version and processor architecture
- Logic Pro installation, version, build, and running state
- Accessibility permission status and remediation

`logic_inspect_ui` is a restricted diagnostic tool. It is absent unless both
the Companion and MCP server start with `LOGIC_ENABLE_DIAGNOSTICS=1`. Its
bounded snapshot contains UI roles, identifiers, focus flags, and child counts,
but deliberately excludes titles, values, descriptions, and UI actions.

The signed Companion runs as a menu-bar app. Its menu continuously reports the
native connection, whether Logic is running, and Exclusive Test Mode status.
Active automation is marked with a red `TEST` label and countdown; a safety
pause is marked in orange with its reason. Pause, resume, and emergency stop are
available from the menu. Test Mode defaults to inactive, expires after at most
one hour, and cannot start until Accessibility and Test Project policy readiness
are both present.

Build and launch the signed Companion, then run the MCP server:

```sh
npm run build:app
open "build/Logic Companion.app"
npm run build
npm start
```

Both processes default to `/tmp/logic-llm-connector-$(id -u).sock`, which the
Companion creates with mode `0600`. To use another path, run the packaged
executable with `--socket <path>` and set the same path in
`LOGIC_COMPANION_SOCKET` for the MCP server.

The local app build is certificate-signed with the configured Apple Development
identity, giving macOS a stable designated requirement across rebuilds. Override
the identity when necessary:

```sh
LOGIC_COMPANION_SIGNING_IDENTITY="Apple Development: Name (ID)" \
  scripts/build-companion-app.sh
```
