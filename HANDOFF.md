# Handoff — 2026-08-23

## Repository state

- Repository: `cotyledonlab/logic-llm-connector` (private)
- Branch: `main`, tracking `origin/main`
- Latest completed implementation commit: `5c0c719`
- Ticket 0012 implementation is committed and pushed, but packaged real-Logic
  acceptance remains incomplete. Do not mark the ticket complete yet.
- Six tracked implementation/acceptance files are intentionally uncommitted and
  listed below. Preserve them when resuming.
- Logic Pro 12.3 was running as PID `58921` when this handoff was written. It is
  blocked in an audio-engine `NSAlert` modal that is not exposed as a normal
  Accessibility/CGWindow window. The user must dismiss this alert before more
  real-Logic acceptance runs.

## Completed and pushed for ticket 0012

The MIDI region and note surface remains implemented across four commits:

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

## Uncommitted work to preserve

Six tracked files are modified:

- `native/LogicCompanion/Sources/LogicBridgeCore/TestProjectLifecycle.swift`
  bounds Accessibility messaging, rejects malformed Logic 12 `AXWindows`
  application proxies, and deterministically reconciles an already-removed
  owned workspace. The experimental `NSWorkspace.open` change was reverted;
  opening again uses the prior asynchronous Apple Event because LaunchServices
  became unreliable in a no-window Logic session.
- `native/LogicCompanion/Sources/LogicBridgeCore/MacLogicMIDIRegionScripting.swift`
  contains two newly diagnosed Logic 12 compatibility fixes that compile but
  have not completed real-Logic acceptance:
  - region `AXPress` can return success without selecting; the adapter raises
    the Tracks window and sets `AXSelected` directly when it is settable, with a
    coordinate fallback;
  - dynamic menu items must be found after opening a top-level menu. The adapter
    now opens menu-bar items before validating and pressing the requested item.
- `native/LogicCompanion/Tests/LogicBridgeCoreTests/TestProjectLifecycleTests.swift`
  adds a passing regression for cleanup after an already-closed workspace was
  externally removed.
- `native/LogicCompanion/Tests/LogicBridgeCoreTests/MacLogicMIDIRegionScriptingTests.swift`
  adds the opt-in four-bar real-Logic round trip: observe fixture regions,
  create, rename, move, resize, update a note, duplicate, split, verify
  playback, delete, and verify Undo.
- `package.json` adds `npm run test:midi-integration`.
- `tests/integration/doctor-stack.test.ts` launches the native four-bar test
  inside the packaged managed-project lifecycle. It still contains temporary
  `/tmp/logic-midi-acceptance-stages.log` diagnostics, stderr stage markers,
  direct workspace removal, and lifecycle-cleanup workarounds inherited from
  the prior debugging session. Remove them before committing. A stage-log reset
  is still misplaced in the first skipped doctor test.

All temporary `[DEBUG-...]` Swift probes and the opt-in 30-second pause were
removed before this handoff. `swift build --package-path native/LogicCompanion`
passes with the current six-file worktree.

## What the latest acceptance established

A clean Logic session allowed the packaged harness to pass the old lifecycle
blocker: the managed fixture opened, closed, and reopened, and the native MIDI
test started. Initial observation then failed quickly.

With `LOGIC_MIDI_ADAPTER_DISCOVERY=1`, the exact path was observed:

1. Logic exposed the correct Tracks window, two tracks, and four raw MIDI
   regions at positions 0, 3840, 7680, and 11520.
2. `AXPress` on the first region returned success but left `AXSelected=false`.
3. Setting `AXSelected=true` succeeded.
4. `Selection as MIDI File…` remained reported disabled while its containing
   menu was dormant.
5. Opening top-level menus caused validation to update, and the export command
   dispatched successfully (`MIDI_ADAPTER_STAGE export menu dispatched`).
6. The operation then failed approximately five seconds later inside
   `completeSavePanel`, before `export saved`. The remaining active defect is
   therefore save-panel discovery or save-panel structure, most likely the
   expected title `Save MIDI File as:` no longer matching Logic 12.3.

The next run intended to log the save-panel title/fields, but Logic stopped
accepting all document-open events first. `NSWorkspace.open`, asynchronous Apple
Events, `open -a`, and `open -F -a` were all ignored in that session.

## Current Logic blocker and disposable workspace

Sampling PID `58921` showed the main thread inside:

```text
MDCA::Idle -> MD::Idle -> CMDLogicInterface::MDalert -> NSAlert runModal
```

The sample is at `/tmp/logic-pro-sample.txt`. Logic exposes no normal window to
Computer Use (`cgWindowNotFound`) and the Accessibility tree exposes only
application/menu proxies, so the alert could not be read or safely dismissed
automatically. Activate Logic manually and dismiss the audio alert, trying
Escape first and Return only if appropriate.

One connector-owned workspace from the last failed open remains at:

```text
/Users/johnmaher/Library/Application Support/Logic LLM Connector/Test Projects/779e4455-81c5-46d5-95e0-f45ea76040e1
```

`lsof` showed that Logic did not have this workspace open when it was left. It
may be reused as a disposable direct-debug copy after Logic recovers, or moved
to Trash after rechecking it is not open. Never open or mutate the source
fixture `~/Music/Logic/LLM Jazz.logicx` directly.

An earlier failed disposable workspace `e8c37fed-...` was moved recoverably to
Trash as `logic-llm-connector-e8c37fed-1e95-4b66-b13a-2221f759c1b8`.

## Resume sequence

1. Dismiss the hidden Logic audio alert and verify Logic is responsive.
2. Confirm Logic has no project open. Recheck the `779e4455-...` workspace with
   `lsof` before reusing it or moving it to Trash.
3. Run the packaged acceptance with discovery enabled:

   ```sh
   LOGIC_TEST_PROJECT_FIXTURE="$HOME/Music/Logic/LLM Jazz.logicx" \
   LOGIC_MIDI_ADAPTER_DISCOVERY=1 \
   npm run test:midi-integration
   ```

4. Instrument only `completeSavePanel` if it again stops after
   `export menu dispatched`. Capture focused/window titles and relevant text
   fields after the export command. Tag temporary logs `[DEBUG-midi-save]` and
   remove them afterward.
5. Continue the four-bar acceptance through `native-pass`, save, close, and
   normal lifecycle cleanup. Restore the harness from its direct-removal
   workaround and remove all stage logging.
6. Run the full validation matrix:

   ```sh
   npm run typecheck
   npm run build
   npm test
   npm run test:package
   LOGIC_TEST_PROJECT_FIXTURE="$HOME/Music/Logic/LLM Jazz.logicx" \
   npm run test:midi-integration
   ```

7. Mark [`0012`](docs/tickets/0012-midi-region-operations.md) and the
   [ticket index](docs/tickets/README.md) complete only after the real-Logic
   acceptance succeeds.
8. Commit and push the acceptance/lifecycle work, then update this handoff for
   ticket 0013 and leave the worktree and Test Projects directory clean.

## Important implementation facts

- TypeScript owns MCP; Swift owns macOS and Logic integration.
- The native seam is JSON-RPC 2.0 over a mode-`0600` Unix socket.
- Both processes default to `/tmp/logic-llm-connector-<uid>.sock`.
- The packaged app is `build/Logic Companion.app`; `build/` is ignored.
- The Companion bundle ID is
  `dev.cotyledonlab.logic-llm-connector.companion` and must retain Accessibility
  and Automation permissions for real-Logic acceptance.
