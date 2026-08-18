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

## Implemented checkpoint

The first verified vertical slice is complete and pushed:

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

Deterministic location verification and its restorable real-Logic acceptance
test remain before this ticket can be marked complete.

## Location investigation

The location transport seam and public `logic_move_playhead` tool are pushed,
but they are not accepted as deterministic. The Companion decodes Mackie
position-display controllers `0x40...0x49`; Logic uses both NUL and space
characters to blank-pad that display, and both are now normalized to zero.

Real-Logic acceptance exposed two unresolved problems:

- Logic sends one full display sweep followed by sparse character updates, so a
  quiet period does not prove that the accumulated display is coherent.
- Equal and opposite jog-wheel messages did not reliably restore the exact
  initial position. One captured sequence was
  `0010101006 → 0010101001 → 0020101001`.

A tested 300 ms quiet-period heuristic still returned the wrong restoration
position and was removed. The exact-restoration acceptance block remains
uncommitted until a protocol-grounded postcondition and reversible locate
strategy are available. The current operation's directional display comparison
must not be considered sufficient real-Logic verification.
