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

## Best next bounded experiment

Do not run the four-bar acceptance.

In `completeOpenPanel(path:)`:

1. After setting the Go-to field to the containing directory, find the first `AXButton` in `descendants(sheet, maximum: ...)` explicitly.
2. Log whether `kAXDefaultButtonAttribute` existed so the branch is unambiguous.
3. Prefer a real `click(at:)` on the untitled button's frame; the panel service has previously ignored semantic AX actions while accepting real mouse clicks.
4. Wait for the sheet to disappear.
5. If it disappears, wait for the exact staged filename `AXStaticText`, click its frame once, and press the enabled `Import` button.
6. Run the narrow test once.

If the real click still does not dismiss the sheet, stop. Inspect the sheet button's frame/actions and take one screenshot rather than retrying the test.

## Current UI/machine state

- Logic Pro is running with the managed project:
  `~/Library/Application Support/Logic LLM Connector/Test Projects/manual-test/LLM Jazz.logicx`
- The last failed narrow test left the Import panel and Go-to sheet open.
- The staged UUID file named in that sheet has already been removed by `defer`.
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
