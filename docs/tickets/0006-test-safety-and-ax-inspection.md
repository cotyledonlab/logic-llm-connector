# 0006 — Add permission and Accessibility inspection

Status: Complete
Depends on: 0005

## Outcome

The Companion proves Accessibility readiness and returns a scrubbed, read-only
snapshot of Logic's visible UI under explicit diagnostic policy.

## Scope

- Accessibility permission onboarding and remediation
- Read-only `logic_inspect_ui` diagnostic tool, disabled by default
- Bounded Logic role, subrole, identifier, enabled, focused, and child-count
  observations without UI text or actions

## Acceptance criteria

- Permission is granted to the packaged Companion identity.
- AX snapshots are bounded, scrubbed, and never invoke UI actions.
- Diagnostic access requires an explicit configuration flag.
- Focus and modal roles are observable within the requested traversal bounds.
- Real-Logic tests pass without mutating the open project.
