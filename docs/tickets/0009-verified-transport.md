# 0009 — Implement verified transport Operations

Status: Pending
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
