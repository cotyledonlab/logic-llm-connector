# 0011 — Add track Operations

Status: Pending
Depends on: 0010

## Outcome

MCP clients can inspect, create, name, select, duplicate, reorder, and delete
supported track types in a Test Project.

## Acceptance criteria

- Software instrument, audio, and external MIDI tracks are covered where Logic
  exposes a verifiable path.
- Track identity survives selection and reorder Operations.
- Destructive deletion is policy-gated and undoable in tests.
- Track count, type, name, and selection are observed after mutations.
- Real-Logic tests restore or discard the Test Project deterministically.
