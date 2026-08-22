# Logic LLM Connector

A local MCP server and macOS companion for verified, programmatic control of
Logic Pro. The project favors semantic music-production operations while using
multiple Logic adapters behind one stable interface.

## Status

Foundation work is in progress. Environment diagnosis, verified transport, the
safe Test Project lifecycle, and verified track operations are supported. MIDI
region operations are the next delivery slice; additional mutating Logic tools
are added only through isolated Test Project acceptance.

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

Track acceptance uses the same no-document and disposable-fixture preconditions.
It creates and names software instrument, audio, and external MIDI tracks, then
verifies selection, duplication, reorder, deletion, Undo availability, save,
close, and cleanup:

```sh
LOGIC_TEST_PROJECT_FIXTURE="/absolute/path/to/Fixture.logicx" \
npm run test:track-integration
```

Project-mutating real-Logic tests will use disposable fixtures and require
explicit test mode. The current integration tests launch the Swift Companion,
connect over a mode-`0600` Unix socket, verify `logic_doctor`, inspect a bounded
text-free Accessibility snapshot, verify focus-loss and emergency-stop safety,
and exercise reversible play/stop plus opt-in project-start location while
restoring the observed transport and Cycle state. They do not edit or save the
open project.

The Test Project lifecycle acceptance is isolated from the ordinary transport
gate. Logic must be running with no document open, and the fixture must be a
saved `.logicx` project that the test may copy. The source is never opened or
modified. This gate has passed against packaged Logic Pro for open, duplicate
rejection, save, close, reopen, cleanup after success, and cleanup after an
injected failure:

```sh
LOGIC_PROJECT_INTEGRATION_TEST=1 \
LOGIC_TEST_PROJECT_FIXTURE="/absolute/path/to/Fixture.logicx" \
npm run test:integration
```

## Current capability

`logic_doctor` reports timestamped evidence for:

- macOS version and processor architecture
- Logic Pro installation, version, build, and running state
- Accessibility permission status and remediation
- CoreMIDI MIDI 1.0 compatibility and virtual endpoint readiness
- visible Mackie Control assignment state and inbound MIDI feedback

`logic_inspect_ui` is a restricted diagnostic tool. It is absent unless both
the Companion and MCP server start with `LOGIC_ENABLE_DIAGNOSTICS=1`. Its
bounded snapshot contains UI roles, identifiers, focus flags, and child counts,
but deliberately excludes titles, values, descriptions, and UI actions.

`logic_play` and `logic_stop` dispatch Mackie Control transport buttons and
report success only after matching feedback returns from Logic. Already-observed
states are idempotent; missing endpoints, feedback timeouts, and dispatch errors
remain explicit. The `logic://transport/state` MCP resource exposes observed
playback, cycle, and record-button readiness state.

`logic_move_playhead` performs bounded relative jogs with coherent Mackie
position-display evidence. `logic_locate` supports the absolute
`project_start` target using Logic's Mackie STOP mapping. It temporarily
disables Cycle when necessary and reports success only after both a fresh
position frame and restoration of the observed Cycle state.

`logic_open_test_project` copies a saved `.logicx` fixture into
`~/Library/Application Support/Logic LLM Connector/Test Projects` before Logic
opens it. `logic_save_test_project`, `logic_close_test_project`,
`logic_reopen_test_project`, and `logic_cleanup_test_project` operate only when
the observed Logic document identity matches that managed copy. Save and
cleanup require explicit confirmation; close rejects unsaved changes. The
`logic://project/state` resource reports the observed front document and whether
the Test Project policy context is verified. Lifecycle commands use Apple
Events without waiting for Logic's reply; structural Accessibility observations
of the document URL and edited flag verify their postconditions, with Apple
Events retained as an observation fallback. A timed-out asynchronous open keeps
its copied workspace until the exact delayed document can be observed, closed,
and safely cleaned.

`logic_list_tracks`, `logic_create_track`, `logic_rename_track`,
`logic_select_track`, `logic_duplicate_track`, `logic_reorder_track`, and
`logic_delete_track` operate only inside the verified managed copy while
Exclusive Test Mode is active. Supported creation types are software
instrument, audio, and external MIDI. Results preserve opaque track IDs and
report the observed ordered list with type, name, position, and selection;
delete requires explicit confirmation and verifies Undo availability. The
`logic://tracks/state` resource provides read-only observation.

The signed Companion runs as a menu-bar app. Its menu continuously reports the
native connection, whether Logic is running, and Exclusive Test Mode status.
Active automation is marked with a red `TEST` label and countdown; a safety
pause is marked in orange with its reason. Pause, resume, and emergency stop are
available from the menu. Test Mode defaults to inactive, expires after at most
one hour, and cannot start or resume until Accessibility and the current managed
Test Project identity are both verified. An identity change pauses automation
and cancels pending UI work.

The Companion also owns stable CoreMIDI MIDI 1.0 virtual endpoints named
`Logic LLM Connector Out` and `Logic LLM Connector In`. Incoming packets are
copied out of CoreMIDI's real-time callback and handed to a dedicated queue;
endpoint loss is observable and recovered without changing endpoint identity.

Mackie Control onboarding is guided from the Companion menu. Doctor classifies
the visible Logic Control Surfaces Setup state as missing, configured, or
conflicting without reading or writing Logic's preference files. See the
[Mackie Control setup guide](docs/mackie-control-setup.md) for idempotent setup,
teardown, and recovery steps.
Real-Logic acceptance requires both the exact visible port assignment and
nonzero Mackie-compatible channel-voice or SysEx feedback.

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
