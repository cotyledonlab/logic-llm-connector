# 0009 — Implement verified transport Operations

Status: In Progress
Depends on: 0008

## Outcome

MCP clients can play, stop, and locate with transport feedback establishing the
postcondition.

## Scope

- Play and stop
- Rewind or locate to a supported position
- Cycle and record-readiness observation
- Transport state resource

## Acceptance criteria

- Commands use the control-surface adapter when supported.
- Feedback, not dispatched input, determines success.
- Focus-independent behavior is tested where Mackie supports it.
- Timeouts and missing feedback produce explicit partial or failed outcomes.
- Real-Logic tests restore the original transport state.

## Implemented progress

- `logic_play` and `logic_stop` use Mackie Control note messages.
- Matching returned transport LED feedback, never dispatch alone, establishes
  success.
- Already-observed play and stop states return idempotent success without a
  redundant command.
- Missing endpoints, dispatch failures, and feedback deadlines return explicit
  failed or timed-out outcomes with partial-effect evidence.
- `logic://transport/state` exposes observed playback, cycle, and record-button
  readiness state.
- Packaged MCP-to-Swift acceptance verifies play and stop while Finder is
  frontmost and restores the original play state in a `finally` block.
- `logic_move_playhead` sends bounded Mackie jog-wheel messages.
- Position feedback is committed only as descending `0x49...0x40` frames.
  Unchanged digits may be omitted and are carried from the prior committed
  frame; isolated sparse updates cannot establish a postcondition.
- The Companion toggles SMPTE/BEATS, waits for a committed refresh, then toggles
  it back and waits for a second committed refresh. This restores the user's
  display mode and provides a protocol-grounded frame boundary.
- Directional movement succeeds only when the final coherent frame moves in the
  requested direction. Missing refreshes or unchanged positions time out.
- A focused packaged real-Logic run moved ten jog detents forward and ten back
  and exactly restored a project-start position.
- `logic_locate` exposes the supported absolute `project_start` target through
  `logic.transport.locate` at the native seam.
- Project-start locate uses Logic's documented Mackie behavior: two STOP
  presses with Cycle disabled, followed by the reversible SMPTE/BEATS refresh
  barrier and a fresh coherent position frame.
- When Cycle is observably enabled, locate disables it, verifies the returned
  LED state, performs the locate, restores Cycle, and verifies restoration.
  Unknown Cycle state fails closed without dispatch.
- The opt-in real-location acceptance now establishes project start, performs a
  relative forward jog, and restores exactly with the absolute locate rather
  than assuming inverse jog symmetry.

The location investigation showed why the earlier quiet-period heuristic was
invalid: Logic emits sparse character changes without a standalone frame-end
message. The reversible display-format refresh supplies explicit descending
start and end controllers while preserving unchanged characters from the last
committed frame.

Relative restoration is not general. A prior full-gate run began at
`0010103009`; equal ten-detent moves and bounded one-detent recovery finished at
`0010101001`, not the initial display. The new absolute project-start path has
contract, MCP, router, and native unit coverage, but its packaged real-Logic
acceptance remains opt-in behind `LOGIC_LOCATION_INTEGRATION_TEST=1` and has not
yet completed in the current UI session. The full-stack rerun is presently
blocked because the packaged AX observer reports `setup_window_closed` while
the Control Surface Setup window is visibly open; a separately launched
Companion also received no fresh Mackie traffic. Ticket 0009 remains in progress
until that environmental observation issue is cleared and the absolute locate
acceptance passes.
