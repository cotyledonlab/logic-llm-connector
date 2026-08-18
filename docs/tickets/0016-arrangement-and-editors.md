# 0016 — Add arrangement, global-track, and editor Operations

Status: Pending
Depends on: 0012, 0013

## Outcome

MCP clients can shape the song structure and use supported specialized Logic
editors without relying on unverified focus state.

## Scope

- Markers, arrangement sections, tempo, meter, key, cycle, and locators
- Piano Roll, Event List, Step Sequencer, Live Loops, and supported editors
- Region folders, takes, comping, and flex features where verifiable

## Acceptance criteria

- Global musical positions share one explicit time model.
- Editor focus and selection preconditions are observed.
- Each advertised editor Capability has a real-Logic fixture and recovery path.
- Unsupported contextual combinations fail explicitly.
