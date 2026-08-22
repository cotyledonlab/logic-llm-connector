# 0011 — Add track Operations

Status: Complete
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

## Delivered

- Public MCP tools inspect, create, rename, select, duplicate, reorder, and
  confirmation-gated delete operations; `logic://tracks/state` exposes the
  observed ordered track list.
- Swift observes Logic track headers and selected-track inspector state,
  preserves opaque identities across rebuilt AX rows, and verifies count,
  type, name, order, and selection postconditions.
- Mutations require both the exact managed Test Project policy context and
  active Exclusive Test Mode. Delete additionally verifies Logic's Undo menu.
- The opt-in packaged acceptance copies the authorized fixture, exercises all
  supported types and operations in real Logic, verifies Logic and document
  identity survive, then saves, closes, and removes only the managed copy.
