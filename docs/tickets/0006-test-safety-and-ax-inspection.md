# 0006 — Add test safety and Accessibility inspection

Status: Pending
Depends on: 0005

## Outcome

The Companion can prove Accessibility readiness and return a scrubbed,
read-only snapshot of Logic's visible UI under explicit diagnostic policy.

## Scope

- Accessibility permission onboarding and remediation
- Companion connection/status visibility
- Exclusive Test Mode indicator, pause, emergency stop, and timeout
- Read-only `logic_inspect_ui` diagnostic tool, disabled by default
- Logic process, window, focus, modal, and project-name observations

## Acceptance criteria

- Permission is granted to the packaged Companion identity.
- AX snapshots are bounded, scrubbed, and never invoke UI actions.
- Diagnostic access requires an explicit configuration flag.
- Losing Logic focus or encountering an unexpected modal is observable.
- Real-Logic tests pass without mutating the open project.
