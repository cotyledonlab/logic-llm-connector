# Handoff — 2026-08-19

## Repository state

- Repository: `cotyledonlab/logic-llm-connector` (private)
- Branch: `main`
- Latest implementation commit: `cb91b6a`
- Last completed acceptance: ticket 0010 packaged Test Project lifecycle
- Specification: [`SPEC.md`](SPEC.md)
- Delivery status: [`docs/tickets/README.md`](docs/tickets/README.md)
- Expected worktree state after this handoff commit: clean and pushed

## Completed tickets

- 0001 — versioned evidence-bearing native bridge contract
- 0002 — public `logic_doctor` MCP tool
- 0003 — native Doctor observations
- 0004 — complete MCP-to-Swift real-Logic tracer bullet
- 0005 — certificate-signed Companion app with stable bundle identity
- 0006 — permission readiness and restricted Accessibility inspection
- 0006b — visible status and Exclusive Test Mode safety state
- 0007 — stable, recoverable CoreMIDI virtual endpoints
- 0008 — repeatable virtual Mackie Control onboarding verified through Logic UI
  and inbound MIDI feedback
- 0009 — feedback-verified play, stop, relative movement, and absolute
  project-start location
- 0010 — safe Test Project open, save, close, reopen, and cleanup through MCP

Ticket 0006 was deliberately split after its tracer bullet proved that AX
inspection and mutable automation safety are separate vertical slices.

## Transport progress

MCP exposes `logic_play`, `logic_stop`, `logic_move_playhead`, and the
`logic://transport/state` resource. Play and stop are established only by newer
matching Mackie LED feedback. Location uses descending position-display frames,
with omitted unchanged digits carried from the prior committed frame. Isolated
sparse updates never establish success.

Playhead movement uses a reversible SMPTE/BEATS refresh barrier: the Companion
waits for one committed frame after switching formats, switches back, and waits
for a second committed frame before comparing direction. This establishes a
coherent directional postcondition, but equal inverse jogs are not a general
restoration mechanism.

MCP now also exposes `logic_locate` with the supported absolute target
`project_start`. The Companion uses Logic's documented Mackie double-STOP
mapping with Cycle disabled, then verifies the result through the reversible
SMPTE/BEATS refresh barrier. If Cycle is observed enabled, it is disabled and
verified before locate, then restored and verified before success. Unknown
Cycle state fails closed without dispatch.

A prior full-gate run showed that inverse jogs are not a restoration mechanism:
it began at `0010103009` and recovered only to `0010101001`. The completed
acceptance therefore establishes project start, moves forward, and restores
with the absolute locate. The opt-in packaged full-stack run passed against real
Logic with Cycle initially enabled, restoring both the exact project-start
display and the observed Cycle state. The open Logic project was not edited or
saved.

### Exclusive Test Mode

The Companion now runs as a menu-bar app and visibly reports native connection,
Logic running state, and automation state. The safety controller:

- defaults to inactive after every launch
- requires Accessibility readiness and a Test Project policy context
- bounds activation to at most one hour and expires automatically
- blocks new UI operations while paused
- cancels registered pending work on environmental interruption or emergency stop
- observes Logic focus loss, unexpected modal windows, and recent keyboard or
  mouse-button input

The menu uses a persistent red `TEST` label with a countdown while active and an
orange `PAUSED` label with the reason after an interruption. A copied Test
Project with matching observed document identity now enables Test Mode. Start
and resume both revalidate Accessibility and project policy readiness; identity
drift pauses automation and cancels pending UI work.

### Test Project lifecycle implementation

Ticket 0010 is complete through the contract, MCP, native bridge, packaged
Companion, deterministic tests, and opt-in real-Logic acceptance. MCP exposes
`logic_open_test_project`,
`logic_save_test_project`, `logic_close_test_project`,
`logic_reopen_test_project`, `logic_cleanup_test_project`, and the
`logic://project/state` resource.

Fixtures are copied before open into mode-`0700` workspaces below
`~/Library/Application Support/Logic LLM Connector/Test Projects`. Apple Events
dispatch lifecycle commands without waiting for Logic's sometimes-blocked
reply. Accessibility observes the standard document URL and close-button edited
flag for non-blocking name, path, and modified-state postconditions, with Apple
Events retained as an observation fallback. Every operation rejects an identity
mismatch; close rejects unsaved changes; visible modal dialogs and Automation
denial fail explicitly. Cleanup closes only the matching managed copy without
saving and removes only its owned workspace.

The packaged acceptance passed on 2026-08-19 using the authorized source fixture
`~/Music/Logic/LLM Jazz.logicx`. It verified MCP open, duplicate-open rejection,
save, close, reopen, cleanup after success, and cleanup after an injected test
failure in 4.81 seconds. Post-run observation found no Logic document and no
connector-owned Test Project workspace; the source fixture was unchanged.
The acceptance starts after a short packaged-Companion settle interval because
Logic processes recreated virtual MIDI endpoints asynchronously.

An acceptance-driven delayed-open case established a further safety invariant:
after dispatch, a missing open postcondition retains the managed workspace and
marks cleanup incomplete. Cleanup will remove it only after the exact delayed
document becomes observable and is closed. Save and close Apple Events target
the recorded project path rather than whichever document happens to be front.

### Virtual MIDI endpoints

The Companion now owns a CoreMIDI MIDI 1.0 virtual source and destination for
its full process lifetime:

- `Logic LLM Connector Out`, unique ID `0x4C4C4D01`
- `Logic LLM Connector In`, unique ID `0x4C4C4D02`

Both advertise `Cotyledon Lab` as manufacturer and
`Logic LLM Connector Control` as model. Timestamped UMP messages loop through
both directions. Destination callbacks copy variable-length packet data from
the original CoreMIDI event-list storage before handing it to a dedicated
dispatch queue; multi-packet input has a regression test. Missing endpoints are
observable, recreated independently with their stable metadata, and retried by
the Companion's existing status cadence.

### Mackie Control onboarding

Logic has one persisted Mackie Control assignment with input
`Logic LLM Connector Out` and output `Logic LLM Connector In`. The Companion
observes the visible Control Surface Setup window without reading or writing
Logic preferences, classifies missing/configured/conflicting assignments, and
records inbound MIDI 1.0 channel-voice and SysEx UMP traffic. Its menu provides
the idempotent setup guide and visible configuration status.

## Current verified capabilities

### `logic_doctor`

Available by default. It observes:

- macOS version and architecture
- Logic Pro installation, bundle, version, build, and running state
- Accessibility trust and remediation
- CoreMIDI MIDI 1.0 protocol compatibility and virtual endpoint readiness
- the visible Mackie Control assignment and inbound Mackie-compatible feedback

### `logic_inspect_ui`

Absent by default. It is registered only when the MCP server starts with
`LOGIC_ENABLE_DIAGNOSTICS=1`, and the Companion independently rejects it unless
started with the same flag.

The result is bounded by `maxDepth` (0–8) and `maxNodes` (1–1000). Nodes contain
role, subrole, identifier, enabled/focused flags, parent, and child count. The
model cannot contain titles, values, descriptions, or UI actions.

### Verified transport

`logic_play`, `logic_stop`, `logic_move_playhead`, and `logic_locate` are public
by default.
Results include the requested state, whether a MIDI command was dispatched, the
observed transport state, reliability, and Mackie feedback evidence.
`logic://transport/state` reports playback plus observed cycle and record-button
readiness. Relative location results carry coherent initial and final Mackie
position frames. Absolute project-start locate supplies an exact supported
target without claiming arbitrary-position restoration.

## Verified local environment

- macOS: 26.5.2
- Architecture: arm64
- Logic Pro: 12.3, build 6674
- Logic bundle: `com.apple.logic10`
- Logic running during the final acceptance test: yes
- Packaged Companion Accessibility trust: granted
- Companion bundle ID: `dev.cotyledonlab.logic-llm-connector.companion`
- Signing authority: `Apple Development: jm547ster@gmail.com (ZMR8R9BPJK)`
- Actual signing TeamIdentifier: `4N63MQVR2B`
- Designated requirement: certificate-backed, not code-hash-backed

Ticket 0010 opened and saved only connector-owned copies. Its authorized source
fixture was never opened or modified. Logic had no document open and the Test
Projects directory was empty after acceptance.

## Validation

Run from the repository root:

```sh
npm run typecheck
npm run build
npm test
npm run test:package
npm run test:integration
LOGIC_LOCATION_INTEGRATION_TEST=1 npm run test:integration
```

The latest non-UI gates passed:

- 10 JSON Schema contract tests
- 4 MCP client tests
- 47 discovered Swift tests, with 3 real-Logic-only cases skipped in the
  ordinary native suite
- certificate-backed package identity test
- packaged, full-stack real-Logic integration tests covered Doctor, default
  diagnostic denial, diagnostic opt-in, bounded AX inspection, MIDI endpoint
  readiness, exact Mackie assignment, inbound Mackie feedback, focus loss,
  emergency stop, focus-independent play/stop, transport state, absolute
  project-start location, forward movement, exact project-start restoration,
  and Cycle-state restoration
- isolated packaged MCP lifecycle acceptance covered open, duplicate rejection,
  save, close, reopen, success cleanup, and injected-failure cleanup

`npm run test:integration` sets `LOGIC_INTEGRATION_TEST=1` and exercises the
running Logic installation through the packaged Companion. The earlier
`setup_window_closed` failure was reproduced while the Setup window was in fact
absent. Reopening the existing assignment restored both AX visibility and fresh
Mackie feedback without any code or configuration change. The focused test and
the complete integration command then passed. Exact location acceptance remains
separately opt-in with `LOGIC_LOCATION_INTEGRATION_TEST=1` because it moves the
playhead. No audio-device choice was made.

## Next work

Begin [`0011 — Track Operations`](docs/tickets/0011-track-operations.md). Add
verifiable inspection, creation, naming, selection, duplication, reorder, and
policy-gated deletion only inside a managed Test Project. Real-Logic tests must
restore or discard their copied project deterministically.

## Important implementation facts

- TypeScript owns MCP; Swift owns macOS/Logic integration.
- The native seam is JSON-RPC 2.0 over a mode-`0600` Unix socket.
- Both processes default to `/tmp/logic-llm-connector-<uid>.sock`.
- The app build is `build/Logic Companion.app`; `build/` is gitignored.
- `scripts/build-companion-app.sh` defaults to this Mac's Apple Development
  signing identity. Override with `LOGIC_COMPANION_SIGNING_IDENTITY` elsewhere.
- The current Unix socket server processes one request per connection
  sequentially. This is adequate for read-only diagnostics but cancellation and
  concurrent operation handling remain future work.
- `ExclusiveTestModeController` is the stable safety gate for future mutating
  adapters. Register pending-operation cancellation before dispatching UI work.
- `AutomationSafetyMonitor` polls only while Test Mode is active; AppKit renders
  snapshots but does not own safety transitions.
- `TestProjectLifecycleController` is the sole owner of managed project context.
  Its default root is under Application Support; never treat an arbitrary open
  document as a Test Project or delete outside the recorded copied workspace.
- Lifecycle mutations dispatch no-reply Apple Events and establish success only
  from the observed Accessibility document URL and edited flag; Apple Events are
  the fallback observer when Accessibility identity is unavailable.
- `VirtualMIDIEndpointOwner` is the stable CoreMIDI seam. It uses MIDI 1.0 UMP,
  preserves host timestamps, serializes endpoint access, and hands receive work
  off the CoreMIDI callback thread.
- `MackieTransportController` owns transport dispatch and verification. Never
  treat a successful `send` as operation success; only a matching newer
  `MackieControlFeedbackMonitor` observation verifies a transition.
- Absolute project-start locate depends on observable Cycle feedback. When Cycle
  is enabled it must be verified disabled before double STOP, and verified
  restored after the position refresh; a fresh position frame alone is not
  sufficient.
- Position display frames begin at controller `0x49`, descend to `0x40`, and may
  omit unchanged digits. Commit only a bounded descending frame; isolated sparse
  updates remain uncommitted.
- `MacMackieControlObserver` is a specialized read-only observer. Its Setup
  window must remain visible when Doctor or real acceptance tests classify the
  assignment.
- The virtual endpoint unique IDs are persisted as source constants, not
  generated at runtime. Do not change them after Logic onboarding begins.
- Native socket failures currently return a generic JSON-RPC internal error;
  structured native error mapping is still needed.
- UI text is intentionally excluded from the diagnostic snapshot. Project
  identity belongs in the later Test Project lifecycle Capability rather than a
  general AX dump.

## Do not do next

- Do not write Logic preference files directly.
- Do not add region or mixer operations before their ordered delivery tickets.
- Do not mutate the currently open Logic project.
- Do not add arbitrary AX actions to `logic_inspect_ui`.
- Do not replace certificate signing with ad-hoc signing; ad-hoc designated
  requirements are tied to the changing code hash and destabilize permissions.
