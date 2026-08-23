# Handoff — 2026-08-23

## Repository state

- Repository: `cotyledonlab/logic-llm-connector` (private)
- Branch: `main`, tracking `origin/main`
- Latest completed implementation commit: `5c0c719`
- Ticket 0012 implementation is committed and pushed, but its packaged real-Logic
  acceptance is still in progress. Do not mark the ticket complete yet.
- The worktree intentionally contains the five uncommitted acceptance/lifecycle
  files listed below. Preserve them when resuming.
- Logic Pro was running with PID `54382` when this handoff was written. Recheck
  its document state and responsiveness before running acceptance.

## Completed and pushed for ticket 0012

The MIDI region and note surface is implemented across four commits:

- `b71b5d3` — explicit musical-time contract and ADR
- `c245b80` — region domain, opaque identity, and deterministic Standard MIDI
  File codec
- `31c5a08` — native bridge, MCP tools/resources, policy gates, and deterministic
  operation tests
- `5c0c719` — real Logic Accessibility adapter, Event Float editing, MIDI
  import/export, playback, split/duplicate/delete, and adapter tests

The public contract uses integer `{ ticks, ppq }` values at 960 PPQ. Region
positions are absolute from project start; note onsets are relative to their
region. MIDI channels are one-based. All mutations retain the managed Test
Project and active Exclusive Test Mode gates.

The production Logic adapter observes arrangement regions through
Accessibility, exports exact note data through a temporary SMF, edits region
name/position/length through Event Float, and imports deterministic SMF data for
create/replace/note edits. Track and MIDI adapters share the same track identity
source.

## Uncommitted work to preserve

Five tracked files are modified:

- `native/LogicCompanion/Sources/LogicBridgeCore/TestProjectLifecycle.swift`
  bounds Accessibility messaging, rejects malformed Logic 12 `AXWindows`
  application proxies, deterministically reconciles an already-removed owned
  workspace, and currently experiments with `NSWorkspace.open` for project
  opening. The new opening mechanism is not yet validated in a healthy Logic
  session and may need to be reverted to the prior asynchronous Apple Event.
- `native/LogicCompanion/Tests/LogicBridgeCoreTests/TestProjectLifecycleTests.swift`
  adds a passing regression for cleanup after an already-closed workspace was
  externally removed.
- `native/LogicCompanion/Tests/LogicBridgeCoreTests/MacLogicMIDIRegionScriptingTests.swift`
  adds the opt-in four-bar real-Logic round trip: observe fixture regions,
  create, rename, move, resize, update a note, duplicate, split, verify playback,
  delete, and verify Undo.
- `package.json` adds `npm run test:midi-integration`.
- `tests/integration/doctor-stack.test.ts` launches the native four-bar test
  inside the packaged managed-project lifecycle. It currently includes temporary
  `/tmp/logic-midi-acceptance-stages.log` diagnostics and stderr stage markers;
  remove those before committing. A `writeFileSync` stage reset was accidentally
  placed in the first, skipped doctor test and must also be removed or moved.

The integration harness currently closes the project, removes the exact verified
connector-owned workspace directly, and asks lifecycle cleanup to reconcile it.
That was a diagnostic workaround for an unhealthy Logic process. Once Logic is
responsive, prefer restoring normal lifecycle cleanup and validate that path.
The `finally` block also temporarily skips cleanup before `managedPath` is set;
restore safe unconditional cleanup handling after the opening failure is fixed.

## Real-Logic acceptance status

The four-bar operation test has compiled but has not reached its native operation
phase. The last packaged attempts failed while opening the managed project copy:

- `logic_open_test_project` reported `postcondition_failed` after 30 seconds with
  `commandDispatched: true` and no observed managed document.
- Later attempts in the same unhealthy Logic process also ignored or hung direct
  Apple Events and `NSWorkspace.open`.
- The temporary stage log reached `cleanup-start` but never `native-start`, so no
  MIDI mutation from this acceptance test has run against Logic yet.

The source fixture is `~/Music/Logic/LLM Jazz.logicx`. It was never opened or
modified. Failed connector-owned copies were confirmed unopened and moved to
Trash, not permanently deleted. Before a new run, inspect
`~/Music/Logic/Logic LLM Connector/Test Projects`; if a failed managed workspace
remains, confirm Logic does not have it open and move only that exact workspace
to Trash.

Resume with Logic open, responsive, and showing no document:

```sh
LOGIC_TEST_PROJECT_FIXTURE="$HOME/Music/Logic/LLM Jazz.logicx" \
npm run test:midi-integration
```

If opening still fails in a healthy session, compare the uncommitted
`NSWorkspace.open` implementation with the previously working asynchronous
Apple Event before changing the MIDI adapter. Avoid repeated acceptance runs
until the managed open/observe postcondition is reliable.

## Validation status

Before the uncommitted acceptance/lifecycle follow-up, these passed:

```sh
npm run typecheck
npm run build
npm test
npm run test:package
```

That checkpoint included 67 native tests; four real-Logic-only tests were
skipped. The new musical-time conversion tests and the new absent-workspace
cleanup regression also passed individually. The current five-file worktree has
not received a final full-suite run.

After real-Logic acceptance passes, remove diagnostics and run:

```sh
npm run typecheck
npm run build
npm test
npm run test:package
LOGIC_TEST_PROJECT_FIXTURE="$HOME/Music/Logic/LLM Jazz.logicx" \
npm run test:midi-integration
```

Stop any already-running built Companion before native tests if CoreMIDI endpoint
unique-ID collisions appear.

## Completion checklist

1. Verify Logic has no document open, is responsive, and no stale managed copy is
   present or in use.
2. Make managed project open/observe reliable and run the packaged MIDI
   acceptance through `native-pass` and cleanup.
3. Restore normal lifecycle cleanup in the harness if the healthy session allows
   it; remove all temporary stage logging.
4. Run the complete validation matrix above.
5. Mark [`0012`](docs/tickets/0012-midi-region-operations.md) and the
   [ticket index](docs/tickets/README.md) complete only after the real-Logic
   acceptance succeeds.
6. Commit the acceptance/lifecycle work, update this handoff for ticket 0013,
   push, and leave the worktree and Test Projects directory clean.

## Important implementation facts

- TypeScript owns MCP; Swift owns macOS and Logic integration.
- The native seam is JSON-RPC 2.0 over a mode-`0600` Unix socket.
- Both processes default to `/tmp/logic-llm-connector-<uid>.sock`.
- The packaged app is `build/Logic Companion.app`; `build/` is ignored.
- The Companion bundle ID is
  `dev.cotyledonlab.logic-llm-connector.companion` and must retain Accessibility
  and Automation permissions for real-Logic acceptance.
