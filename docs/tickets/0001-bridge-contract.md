# 0001 — Define the native bridge contract

Status: Complete
Depends on: None
Commits: `ea191f3`, `f2a0b12`

## Outcome

A committed JSON Schema defines versioned, traceable JSON-RPC doctor requests
and evidence-bearing outcomes across the native seam.

## Acceptance criteria

- Valid doctor requests include protocol and operation IDs.
- Successful results require non-empty Evidence.
- Unknown readiness can be represented without being reported as observed.
- Contract tests pass and the schema is documented.
