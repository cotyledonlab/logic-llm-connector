# 0010 — Implement Test Project lifecycle

Status: Pending
Depends on: 0006, 0009

## Outcome

The connector safely opens, identifies, saves, closes, and reopens disposable
Test Projects.

## Acceptance criteria

- A dedicated test directory and copied fixture policy are enforced.
- Open, save, close, and reopen have observed project-identity postconditions.
- Unsaved-change and template dialogs are handled or fail explicitly.
- Cleanup succeeds after both successful and failed tests.
- User projects are rejected while Exclusive Test Mode is active.
