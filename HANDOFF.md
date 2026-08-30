# Handoff — 2026-08-29 — MIDI import panel isolated

## Scope and repository state

- Repository: `cotyledonlab/logic-llm-connector`
- Branch: `main`
- Starting/pushed HEAD: `0767173 docs(handoff): capture MIDI panel-automation debugging session`
- Six implementation files are modified and uncommitted:
  - `native/LogicCompanion/Sources/LogicBridgeCore/MacLogicMIDIRegionScripting.swift`
  - `native/LogicCompanion/Sources/LogicBridgeCore/TestProjectLifecycle.swift`
  - `native/LogicCompanion/Tests/LogicBridgeCoreTests/MacLogicMIDIRegionScriptingTests.swift`
  - `native/LogicCompanion/Tests/LogicBridgeCoreTests/TestProjectLifecycleTests.swift`
  - `package.json`
  - `tests/integration/doctor-stack.test.ts`
- Preserve all six files. They include substantive fixes from the prior session plus the work described below.
- Ticket 0012 is not complete. Do not mark it complete until the real-Logic MIDI acceptance is green.

## User constraint

Keep the next slice small. The user explicitly wants context/time conserved and does not want repeated full acceptance runs that cycle through region export menus. Use the narrow import-panel test below. Stop after one bounded experiment if it does not produce new evidence.

## What is working

- `swift test` passed 70/70 tests after adding the narrow import-panel test and before the final directory-path adjustment. The final code still compiles in the targeted test build.
- `npm run typecheck` passed in this session.
- A full real-Logic run successfully exported all four existing regions multiple times. Each temporary SMF was 131–132 bytes and was deleted after decoding.
- The adapter stages the import SMF in `~/Downloads` and removes it with `defer`, including after failure.
- Logic activation was flaky through Apple Events alone. Both the adapter and real-Logic test helper now fall back to `/usr/bin/open -a "Logic Pro"`; this made Logic frontmost reliably.
- The managed project identity is observable through Apple Events.

## Narrow acceptance added

`MacLogicMIDIRegionScripting` now has a `#if DEBUG` internal seam:

```swift
exerciseImportPanelForAcceptance(trackID:position:length:notes:)
```

It deliberately avoids `observeRegions()` and therefore performs no MIDI exports. It:

1. Records the current raw region elements.
2. Imports a one-note staged MIDI file through the real Logic UI.
3. Finds the newly created raw region.
4. Deletes the probe region before returning.

The opt-in test is:

```text
LogicBridgeCoreTests.realLogicMIDIImportPanelRoundTrip
```

Run only it with:

```sh
cd native/LogicCompanion
LOGIC_MIDI_IMPORT_PANEL_TEST=1 \
LOGIC_MIDI_ADAPTER_DISCOVERY=1 \
LOGIC_MANAGED_TEST_PROJECT_PATH="$HOME/Library/Application Support/Logic LLM Connector/Test Projects/manual-test/LLM Jazz.logicx" \
caffeinate -d -i -m swift test --filter LogicBridgeCoreTests.realLogicMIDIImportPanelRoundTrip
```

This test reaches the Import panel in about ten seconds and does not open any export/save menus.

## Exact current blocker

The narrow test consistently reaches:

```text
MIDI_ADAPTER_STAGE import: staged llm-import-<uuid>.mid
MIDI_ADAPTER_STAGE import: track selected
MIDI_ADAPTER_STAGE import: playhead set
MIDI_ADAPTER_STAGE import: menu dispatched
MIDI_ADAPTER_STAGE open panel found
MIDI_ADAPTER_STAGE open panel: Go to Folder submit=0
MIDI_ADAPTER_STAGE open panel: Go to Folder sheet did not dismiss
```

`0` is `AXError.success`, but the sheet remains visible.

Read-only AX inspection proved:

- The Go-to sheet exists as an `AXSheet` under the `Import` window.
- Its text field contains the exact staged path and reports focused `true`.
- The field exposes `AXConfirm`.
- The sheet contains exactly one untitled `AXButton`, almost certainly the visible Go button.
- Calling `AXConfirm` reports success but does not dismiss the sheet.
- The current code asks for `kAXDefaultButtonAttribute` and falls back to `AXConfirm`, but the log does not say which branch ran. It is likely that `kAXDefaultButtonAttribute` is absent and the explicit untitled button has never actually been pressed.
- Supplying the full file path and supplying the containing directory (`~/Downloads`) both left the sheet open with the current submit logic.

## 2026-08-30 bounded experiment result

The prescribed explicit-button experiment was run once with the narrow test.
Before the valid run, two setup attempts failed before import: Logic initially
had no project open, then a transient `UserNotificationCenter` banner stole
frontmost focus. Reopening the exact managed project, dismissing the known
audio-interface alert, and allowing the banner to clear restored the test
preconditions.

The valid run reached the Go-to sheet and proved:

- `kAXDefaultButtonAttribute` is absent.
- The sheet has one untitled enabled `AXButton`, frame
  `{{932, 225}, {18, 18}}`, exposing only `AXPress`.
- A real mouse click on that frame did not submit the sheet; it cleared the
  text field. The button is the field's clear control, not a Go button.
- A screenshot after the click showed the focused field visibly empty with
  recent paths below it. Read-only AX inspection also reported `value: ""`,
  `focused: true`, frame `{{520, 223}, {344, 22}}`, and actions
  `AXShowMenu, AXConfirm`.
- The staged file was removed by `defer`; no MIDI region was imported.
- The failed experimental source change was reverted. Only this handoff update
  remains from the experiment.

## Best next bounded experiment

Do not run the four-bar acceptance.

In `completeOpenPanel(path:)`:

1. Keep the real click that focuses the Go-to text field, but do not use
   `AXUIElementSetAttributeValue` and do not click the untitled button.
2. Clear/select the field with Command-A and enter the containing Downloads
   path through the existing System Events `typeText`/key-delivery seam, so the
   remote panel receives real keyboard input.
3. Read the field's AX value back and require it to equal the directory before
   submitting. Log only the equality result, not a broad UI dump.
4. Press Return through `pressKey(36)` and wait for the sheet to disappear.
5. If it disappears, wait for the exact staged filename `AXStaticText`, click
   its frame once, and press the enabled `Import` button.
6. Run the narrow test once, with a short delay before it so any transient
   `UserNotificationCenter` completion banner cannot steal Logic focus.

If real keyboard entry does not make the AX value match the directory, stop
and capture one screenshot. If the value matches but Return does not dismiss
the sheet, stop and inspect whether the field's Return key event reaches the
remote panel; do not retry the test.

## 2026-08-30 keyboard-entry experiment result

The prescribed keyboard-entry experiment was run once with the narrow test.
It reached the Import panel, but the exact AX readback comparison was false.
The requested single screenshot revealed that Command-Shift-G had been routed
to Logic itself: it opened Logic's `Go To Position` sheet over the Import
panel, rather than Finder's Go-to-Folder sheet. The typed Downloads path was
then interpreted across Logic's musical-position fields. This explains why
the expected directory never appeared in the field.

The failed experimental source change was reverted and the test was not
retried. The staged UUID file was removed by `defer`. The screenshot is a
temporary local artifact at:

```text
/tmp/logic-import-panel.BddMiT/keyboard-entry-failed.png
```

The next bounded experiment should avoid keyboard shortcuts entirely. The
Import panel visibly exposes `Downloads` in its sidebar, matching the adapter's
staging directory. Click that sidebar item by its AX frame, wait for the exact
staged filename, select it, and press the enabled `Import` button. Do not use
Go-to-Folder or run the four-bar acceptance.

## Current UI/machine state

- Logic Pro is running with the managed project:
  `~/Library/Application Support/Logic LLM Connector/Test Projects/manual-test/LLM Jazz.logicx`
- The last failed narrow test left the Import panel and Logic's `Go To Position`
  sheet open with the typed path distributed across its position fields.
- The staged UUID file from that run has already been removed by `defer`.
- No `swift test`, test bundle, or test `caffeinate` process is running.
- One old unrelated probe remains: `~/Downloads/llm-import-probe.mid` (41 bytes).
- Logic may show this launch alert after restart:
  `The last selected audio interface is not available.`
  Pressing its `OK` button is sufficient; do not open Settings.
- The source fixture remains:
  `~/Music/Logic/LLM Jazz.logicx`
- The managed project copy is approximately 652 KB. Temporary exports are tiny and do not accumulate.

## Safe reset before a narrow run

Because the current sheet points at a deleted staged file, cancel the sheet and Import panel or restart only Logic, reopening the managed copy. A Logic restart can show the audio-interface alert described above. Do not delete the source fixture.

## Other existing changes that still need final cleanup

- `TestProjectLifecycle.swift` uses bounded `/usr/bin/osascript` subprocesses instead of in-process `NSAppleScript` and defers ambiguous AX observations to Apple Events.
- Lifecycle regression coverage for an already-absent workspace is present.
- `package.json` contains `test:midi-integration`.
- `doctor-stack.test.ts` contains the packaged MIDI acceptance wiring. Review it for temporary stage diagnostics before the final commit.
- `MacLogicMIDIRegionScripting.swift` contains extensive `LOGIC_MIDI_ADAPTER_DISCOVERY=1` diagnostics and one duplicated `setSegments` comment that can be trimmed during final cleanup.

## Completion path after the narrow test turns green

1. Run all native tests.
2. Run the standalone four-bar acceptance once against the managed copy.
3. Run `npm run typecheck`, normal tests/build/package checks, then the packaged MIDI acceptance once.
4. Remove temporary diagnostics from `doctor-stack.test.ts`; retain useful opt-in adapter diagnostics.
5. Mark ticket 0012/index complete only after packaged acceptance passes.
6. Commit with the workspace-required message format and push.
