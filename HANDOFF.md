# Handoff — 2026-08-22

## Repository state

- Repository: `cotyledonlab/logic-llm-connector` (private)
- Branch: `main`
- Latest implementation commits: `8256249`, `f57758d`
- Last completed acceptance: ticket 0011 verified track operations
- Specification: [`SPEC.md`](SPEC.md)
- Delivery status: [`docs/tickets/README.md`](docs/tickets/README.md)
- Expected state after the handoff commit: clean and pushed

## Completed work

Tickets 0001 through 0011 are complete. Ticket 0011 adds:

- `logic_list_tracks`, `logic_create_track`, `logic_rename_track`,
  `logic_select_track`, `logic_duplicate_track`, `logic_reorder_track`, and
  confirmation-gated `logic_delete_track`
- `logic://tracks/state`
- software instrument, audio, external MIDI, and unknown observed types
- opaque identity reconciliation across Logic AX row rebuilds and reorder
- count, type, name, selection, order, and Undo postcondition evidence
- managed Test Project and active Exclusive Test Mode gates for every mutation

The native implementation uses Logic menu commands plus bounded Accessibility
gestures. Inline rename re-resolves Logic's focused editor after double-click.
Reorder uses an interpolated interior-header drag. Menu-backed commands dismiss
lingering menus so project lifecycle commands are not blocked. Track creation
and duplication carry the requested/source type into the newly observed row,
rather than inferring from stale controls elsewhere in Logic's AX tree.

Managed cleanup now retries one ignored asynchronous close command, but only
after re-observing that the same exact connector-owned project is still open.
A deterministic regression test covers this reconciliation.

## Real-Logic acceptance

Run only with Logic open and no document loaded:

```sh
LOGIC_TEST_PROJECT_FIXTURE="/absolute/path/to/Fixture.logicx" \
npm run test:track-integration
```

The packaged acceptance copies the fixture, opens/saves/closes/reopens the
managed copy, then creates and names all three supported track types, selects,
duplicates, reorders, deletes, verifies Undo availability, verifies the same
Logic PID and exact managed document remain alive, saves settled changes, and
cleans the owned workspace.

The final run passed against Logic Pro 12.3 using
`~/Music/Logic/LLM Jazz.logicx`. The source fixture was never opened or
modified, the Test Projects directory was empty afterward, and no new Logic
crash report was produced. Several failed development runs left disposable
connector-owned copies; they were moved to Trash after Logic was confirmed not
to have them open, so they remain recoverable.

Logic presents an audio-interface warning on a fresh launch when the previously
selected device is unavailable. Dismiss that warning and the project chooser
before running isolated acceptance; production commands correctly fail closed
while a modal dialog is present.

## Validation

Run from the repository root:

```sh
npm run typecheck
npm run build
npm test
npm run test:package
```

The ordinary Swift suite discovers 55 tests; four real-Logic-only cases skip
unless explicitly enabled. The track acceptance is separately opt-in because
it mutates a disposable Logic project copy.

## Next work

Begin [`0012 — MIDI region and note Operations`](docs/tickets/0012-midi-region-operations.md).
Define an explicit musical-time representation before exposing mutations, then
add region/note identity and fidelity postconditions. Preserve the existing
rule: all real-Logic mutation tests operate only on copied managed fixtures and
must deterministically save/close or discard them.

## Important implementation facts

- TypeScript owns MCP; Swift owns macOS and Logic integration.
- The native seam is JSON-RPC 2.0 over a mode-`0600` Unix socket.
- Both processes default to `/tmp/logic-llm-connector-<uid>.sock`.
- The packaged app is `build/Logic Companion.app`; `build/` is ignored.
- The Companion bundle ID is
  `dev.cotyledonlab.logic-llm-connector.companion` and must retain Accessibility
  and Automation permissions for real-Logic acceptance.
