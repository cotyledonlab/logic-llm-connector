# 0017 — Add import, export, and bounce Operations

Status: Pending
Depends on: 0010, 0012, 0013, 0014

## Outcome

MCP clients can exchange supported project material and render deliverables
with explicit format and overwrite policies.

## Acceptance criteria

- MIDI, audio, and applicable AAF/XML/MusicXML flows declare fidelity.
- Bounce parameters, range, normalization, tail, and destination are explicit.
- External writes and overwrites require policy approval.
- Output existence, metadata, duration, and non-empty media are verified.
- Cancelled or failed renders leave predictable artifacts and recovery advice.
