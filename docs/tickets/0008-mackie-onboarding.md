# 0008 — Onboard virtual Mackie Control

Status: Complete
Depends on: 0006b, 0007

## Outcome

Logic Pro is repeatably configured to use the Companion's virtual Mackie
Control endpoint without directly mutating undocumented preference files.

## Acceptance criteria

- Doctor detects whether the expected control surface is configured.
- A guided setup path handles a clean Logic profile.
- Setup is idempotent and detects conflicting assignments.
- Configuration is verified from Logic UI and MIDI feedback.
- Teardown/recovery instructions are documented.

## Acceptance evidence

- The certificate-signed Companion is trusted for Accessibility.
- Logic Pro 12.3's visible Control Surface Setup window reports one Mackie
  Control with input `Logic LLM Connector Out` and output
  `Logic LLM Connector In`.
- Doctor classifies that exact assignment as configured and reports inbound
  Mackie-compatible CoreMIDI channel-voice and SysEx traffic.
- The real-Logic integration test asserts the permission, exact UI assignment,
  and nonzero feedback while managing the packaged Companion lifecycle to
  avoid stable endpoint identity collisions.
- Setup, idempotence, conflict recovery, and teardown are documented in
  [`docs/mackie-control-setup.md`](../mackie-control-setup.md).
