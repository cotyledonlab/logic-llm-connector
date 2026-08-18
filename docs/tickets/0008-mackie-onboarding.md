# 0008 — Onboard virtual Mackie Control

Status: Pending
Depends on: 0006, 0007

## Outcome

Logic Pro is repeatably configured to use the Companion's virtual Mackie
Control endpoint without directly mutating undocumented preference files.

## Acceptance criteria

- Doctor detects whether the expected control surface is configured.
- A guided setup path handles a clean Logic profile.
- Setup is idempotent and detects conflicting assignments.
- Configuration is verified from Logic UI and MIDI feedback.
- Teardown/recovery instructions are documented.
