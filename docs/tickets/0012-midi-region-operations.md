# 0012 — Add MIDI region and note Operations

Status: Pending
Depends on: 0011

## Outcome

MCP clients can create, inspect, move, resize, duplicate, split, and edit MIDI
regions and their musical events.

## Acceptance criteria

- Notes preserve pitch, onset, duration, velocity, and channel.
- Region positions and lengths use an explicit musical time representation.
- Bulk MIDI import and editor-driven changes report fidelity differences.
- Playback verifies that the resulting region is active in the arrangement.
- A deterministic four-bar MIDI fixture round-trips through Logic.
