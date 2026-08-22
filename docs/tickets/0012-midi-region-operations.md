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

## Contract decisions

- Musical time is `{ ticks, ppq }`, using integer quarter-note subdivisions at
  960 PPQ. Region positions are absolute from project start; note onsets are
  relative to their region. See [ADR 0005](../adr/0005-use-explicit-quarter-note-ticks.md).
- MIDI channels are one-based (`1...16`) at the public boundary. Pitch and
  velocity use MIDI's integer ranges, with note velocity restricted to `1...127`.
- Region and Note identities are opaque. Operations return the complete observed
  region set plus field-level Fidelity Differences; requested or imported values
  are not presented as observed when Logic cannot verify them.
- The deterministic acceptance fixture is four bars of 4/4: 15,360 ticks at
  960 PPQ, with notes chosen to cover overlapping onsets, multiple velocities,
  and multiple channels.
