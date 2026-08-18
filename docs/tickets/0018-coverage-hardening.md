# 0018 — Harden coverage for the first release

Status: Pending
Depends on: 0001–0017

## Outcome

The connector publishes an audited Capability catalog covering the common
end-to-end production workflow and labels every remaining gap honestly.

## Acceptance criteria

- Capability discovery matches implemented and tested Operations.
- The full blank-project acceptance scenario completes and cleans up.
- Compatibility is retested against supported Logic/macOS profiles.
- Recovery, cancellation, timeouts, logs, screenshots, and redaction are
  exercised through fault injection.
- MCP Inspector, unit, contract, package, and real-Logic suites pass.
- Installation, permissions, safety, operation, and troubleshooting docs are
  complete.
- A prioritized post-release coverage backlog records unsupported Logic areas.
