# 0015 — Add plugin and automation Operations

Status: Pending
Depends on: 0011, 0014

## Outcome

MCP clients can load, remove, bypass, reorder, configure, and automate
supported instruments and effects.

## Acceptance criteria

- Plugin discovery records vendor, name, type, availability, and validation
  status when observable.
- Loading and removal are verified by slot identity.
- Exposed parameters and presets have stable semantic identifiers.
- Automation mode, parameter, position, and value are verified.
- Arbitrary plugin UI control is separately classified as UI-driven and never
  implied by general plugin support.
