# Handoff — 2026-08-23 (evening, after computer-use debugging session)

## Repository state

- Repository: `cotyledonlab/logic-llm-connector`, branch `main`
- Latest pushed commit: `e05f5ec` (handoff checkpoint). Ticket 0012 implementation
  commits `b71b5d3`, `c245b80`, `31c5a08`, `5c0c719` are pushed.
- **Six uncommitted modified files** (was five in the previous handoff; one was
  added). All contain substantive, working fixes — preserve them:
  1. `native/LogicCompanion/Sources/LogicBridgeCore/TestProjectLifecycle.swift`
     - `observeUsingAccessibility()` now ALWAYS returns `.unavailable` when the
       AX walk yields no logicx document (empty windows list, plugin windows,
       malformed Logic 12 proxies, windowless-open-document states) so the
       Apple Events fallback decides document identity. This fixed false
       "no project open" observations.
     - `execute()` now runs AppleScript through the **`/usr/bin/osascript`
       subprocess** (bounded 30s manual wait, stderr-based -1743 detection)
       instead of in-process `NSAppleScript`, which deadlocks when the calling
       thread drains the main queue (swift-testing does).
  2. `native/LogicCompanion/Sources/LogicBridgeCore/MacLogicMIDIRegionScripting.swift`
     Major rework of the panel automation (details in "What was broken" below):
     - `pressKey` → System Events `key code N` via osascript subprocess
       (raw CGEvents never reach Logic's remotely-hosted save/open panels).
     - Export flow: save panel defaults to the open project's directory.
       `exportedNotes` queries the document directory once (osascript, retried,
       cached in `cachedDocumentDirectory`), sets a unique filename
       `llm-export-<uuid>` WITHOUT extension (panel mangles names that carry
       `.mid`), presses Save via AX, then globs the directory for `stem*`.
     - Import flow: staged file is written INTO the document directory
       (`llm-import-<uuid>.mid`); `completeOpenPanel(filename:)` waits for the
       panel titled "Import"/"MIDI"/with an Open button (search 2000 nodes),
       finds the file's AXStaticText row, presses it, then Return + Open.
       **This step is the current blocker** — see below.
     - `select()` raises the cached Tracks window, tolerates AXPress failure,
       falls back to AXSelected when settable, retries press once after 0.3s.
     - `exportedNotes` re-resolves the live region element by signature
       (trackID/name/position/length) before selecting — modal panel sessions
       rebuild the arrangement AX tree and invalidate captured elements
       (-25202 errors otherwise).
     - `setSegments` accepts fewer sliders than values (condensed LCD shows
       only bar/beat; old code required exactly 4).
     - `performMenuItem` activates Logic first via `activateLogic()`
       (osascript `tell app id ... to activate`) because background apps'
       menu bars are not AX-exposed; `logicApplication(requireFocus: true)`
       also activates before throwing.
     - `discoveryLog` gated by `LOGIC_MIDI_ADAPTER_DISCOVERY=1` prints
       `MIDI_ADAPTER_STAGE ...` lines; several step logs were added during
       debugging and are useful — keep or trim.
  3. `native/LogicCompanion/Tests/LogicBridgeCoreTests/MacLogicMIDIRegionScriptingTests.swift`
     (the opt-in four-bar real-Logic test; unchanged in content from the
     earlier handoff but still modified/uncommitted)
  4. `native/LogicCompanion/Tests/LogicBridgeCoreTests/TestProjectLifecycleTests.swift`
     (absent-workspace cleanup regression)
  5. `package.json` (`test:midi-integration` script)
  6. `tests/integration/doctor-stack.test.ts`
     (packaged lifecycle + native four-bar test; still contains temporary
     `/tmp/logic-midi-acceptance-stages.log` stage logging and a stray
     `writeFileSync` stage reset in the first, skipped doctor test — REMOVE
     before committing)

- Native unit tests: **69/69 pass** (`cd native/LogicCompanion && swift test`).
- The four real-Logic-only tests remain skipped without env flags.

## What was broken and what fixed it (context for the next agent)

The real-Logic MIDI acceptance never ran before today. Root causes found,
all fixed in the working tree:

1. **In-process NSAppleScript deadlocks** under swift-testing (calling thread
   drains the main queue; the Apple Event reply can never be pumped). Fixed by
   routing ALL AppleScript (execute, pressKey, currentDocumentDirectory,
   activateLogic) through the osascript SUBPROCESS.
2. **Raw CGEvent keyboard posts never reach Logic's panels** (they are hosted
   by the openAndSavePanelService XPC). System Events `key code` works.
   Mouse CGEvents DO work (used by click/drag).
3. **Go-to-folder sheet (Cmd+Shift+G) is unusable programmatically**: its text
   field needs a real mouse click for keyboard focus, and Return only commits
   then. Abandoned entirely: save panel defaults to the project directory, so
   exports save there and imports stage files there. No navigation needed.
4. **Save panel mangles filenames ending in `.mid`** (produces
   `<name>.mid     .mid`). Set the stem only.
5. **AX tree invalidation after each modal panel session**: region elements
   captured before an export die (-25202). Re-resolve by signature per export.
6. **Condensed LCD**: only 2 playhead sliders exist; setSegments required 4.
7. **Background menu bars aren't AX-visible**: activate Logic (via AE) before
   menu dispatch.
8. **observe() false negatives**: windowless-open-document and proxy-window
   states now defer to the Apple Events fallback.

## Verified working state (screen awake + unlocked)

- Initial four-bar observe: PASSES end-to-end — all 4 regions found with
  exact notes via SMF export (131/132 bytes each), repeatedly.
- `create` (import) reaches the Open panel and finds it, but the staged file
  ROW is not found in the panel browser — "open panel: staged file row not
  found". Manual exploration showed the panel browser may display an empty or
  wrong folder (sidebar-only static texts). NEXT STEP is to fix row selection:
  options: (a) check the panel's current directory and use Cmd+Shift+G with
  the click-field-then-Return dance (works manually: click the sheet's text
  field via CGEvent mouse click at its frame, AX-set value, key code 36,
  then key code 36 again to Open); (b) type-select by keystroking the
  filename; (c) investigate why the browser shows no rows — possibly the
  browser needs the panel expanded or the directory refreshed.
- After create succeeds, the rest of the four-bar test (rename, move, resize,
  update note, duplicate, split, playback verify, delete, undo) has never run
  — expect more panel-session fallout to fix, but the patterns above are the
  toolkit.

## Environment / operational facts learned

- **The Mac locking/sleeping breaks everything** (black screenshots, AX trees
  degrade to recursive "Logic Pro" proxies, activations fail). Before running
  acceptance: unlock the Mac, then `caffeinate -d -t 1800 &` to keep the
  display awake. Verify with `screencapture -x` that the screen is not black.
- A killed test leaves orphaned modal panels ("Save MIDI File as:", "Import")
  that block all subsequent Apple Events. Dismiss via System Events Cancel
  press (deep walk with `entire contents`) while Logic is frontmost, or
  `pkill -x "Logic Pro"` and relaunch.
- After closing documents via Apple Events, Logic often holds the doc with NO
  AX windows. observe() handles it, but rawRegions (Tracks window) will not —
  reopen the project and verify windows via System Events first.
- The managed Test Projects dir is `~/Library/Application Support/Logic LLM
  Connector/Test Projects/` (NOT ~/Music — old handoff path was wrong).
  Stale workspace dirs there are safe to delete when Logic has 0 documents.
- The source fixture `~/Music/Logic/LLM Jazz.logicx` has never been modified.
- A manual-test workspace exists at
  `.../Test Projects/manual-test/LLM Jazz.logicx` (created by debugging; the
  swift four-bar test was driven against it directly with
  `LOGIC_MANAGED_TEST_PROJECT_PATH`). Safe to delete.
- Safari was fullscreen on Space 1 during the session; clicks/activations
  interacted with it. Be careful with blind coordinate clicks.

## How to run the four-bar test standalone (fast iteration)

```sh
# Logic running, managed copy open, screen unlocked, caffeinate -d running
cd native/LogicCompanion
LOGIC_MIDI_INTEGRATION_TEST=1 \
LOGIC_MIDI_ADAPTER_DISCOVERY=1 \
LOGIC_MANAGED_TEST_PROJECT_PATH="$HOME/Library/Application Support/Logic LLM Connector/Test Projects/manual-test/LLM Jazz.logicx" \
swift test --filter LogicBridgeCoreTests.realLogicMIDIOperationsRoundTripFourBars
```

Stage log appears on stdout as `MIDI_ADAPTER_STAGE ...` lines.

## Full packaged acceptance (the actual ticket gate)

```sh
LOGIC_TEST_PROJECT_FIXTURE="$HOME/Music/Logic/LLM Jazz.logicx" \
npm run test:midi-integration
```

Requires: Logic running with NO document open (test precondition), screen
unlocked. It copies the fixture, opens it via the Companion lifecycle, runs
the native four-bar test inside, then cleans up. Watch
`/tmp/logic-midi-acceptance-stages.log` (temporary; stages: opened →
reopened → native-start → native-pass → cleanup-done).

## Current machine state (as of handoff)

- Logic Pro running (PID 79282), 0 documents, one small startup dialog
  (260x284 at 605,193) on a LOCKED screen — dismiss or relaunch Logic first.
- Two stale managed workspaces in Test Projects (`3f69b7c2…`, `d722e132…`)
  — safe to delete when Logic has 0 documents.
- `/tmp/swift-test.log`, `/tmp/midi-run.log` hold last run output.

## Completion checklist (updated)

1. Unlock Mac, `caffeinate -d -t 1800 &`, dismiss/relaunch Logic.
2. Fix `completeOpenPanel` row selection (the one remaining known blocker).
3. Drive the standalone four-bar test to green against `manual-test`.
4. Reset: close docs, remove manual-test + stale workspaces, fresh fixture.
5. Run the full packaged acceptance to `native-pass` and `cleanup-done`.
6. Remove temporary diagnostics (doctor-stack stage log/writeFileSync; trim
   discoveryLog lines if desired), run: typecheck, build, npm test,
   test:package, then the packaged acceptance again.
7. Mark ticket 0012 + index complete, commit (all six files), update this
   handoff for 0013, push, leave worktree and Test Projects clean.
