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

Location navigation and its restorable real-Logic acceptance test remain before
this ticket can be marked complete.
