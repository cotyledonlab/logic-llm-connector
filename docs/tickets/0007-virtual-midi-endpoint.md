# 0007 — Create the virtual MIDI endpoint

Status: Pending
Depends on: 0005

## Outcome

The Companion owns stable CoreMIDI virtual source and destination endpoints and
can exchange timestamped MIDI messages without blocking real-time callbacks.

## Acceptance criteria

- Endpoint names and identities remain stable across launches.
- MIDI protocol/version compatibility is reported by Doctor.
- Send and receive loopback tests pass.
- Callback work is non-blocking and handed off safely.
- Endpoint removal/reappearance is reported and recoverable.
