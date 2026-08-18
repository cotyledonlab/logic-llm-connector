# 0014 — Add mixer and routing Operations

Status: Pending
Depends on: 0009, 0011

## Outcome

MCP clients can inspect and set channel-strip levels, pan, mute, solo, sends,
buses, and supported input/output routing.

## Acceptance criteria

- Normalized control-surface values map to documented semantic values.
- Readback verifies each supported mixer mutation.
- Stereo, mono, instrument, aux, output, and master strip differences are
  represented explicitly.
- Feedback bank changes cannot silently target the wrong channel strip.
- A mixer-state fixture round-trips within declared tolerances.
