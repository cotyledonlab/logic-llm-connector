# 0010 — Implement Test Project lifecycle

Status: Complete
Depends on: 0006b, 0009

## Outcome

The connector safely opens, identifies, saves, closes, and reopens disposable
Test Projects.

## Acceptance criteria

- A dedicated test directory and copied fixture policy are enforced.
- Open, save, close, and reopen have observed project-identity postconditions.
- Unsaved-change and template dialogs are handled or fail explicitly.
- Cleanup succeeds after both successful and failed tests.
- User projects are rejected while Exclusive Test Mode is active.

## Implemented

- The Companion copies saved `.logicx` fixtures into a mode-`0700` workspace
  below `~/Library/Application Support/Logic LLM Connector/Test Projects`.
- Apple Events dispatch open, save, close, and reopen without waiting for
  Logic's reply. Accessibility observes the standard document URL and edited
  flag for identity postconditions, with Apple Events as fallback.
- User documents, identity drift, unsaved close, Automation denial, and visible
  modal dialogs fail explicitly without treating dispatch as success.
- Cleanup closes only the matching managed copy without saving and removes only
  its connector-owned workspace. Unit and MCP tests cover cleanup after both a
  successful flow and an injected failure.
- A verified managed project enables Exclusive Test Mode. Losing that identity
  pauses automation and cancels pending UI work; resume revalidates the policy.

## Verified acceptance

The opt-in packaged MCP-to-Logic lifecycle passed on 2026-08-19 with Logic
showing no open document and a copied disposable fixture:

```sh
LOGIC_PROJECT_INTEGRATION_TEST=1 \
LOGIC_TEST_PROJECT_FIXTURE="$HOME/Music/Logic/LLM Jazz.logicx" \
npm run test:integration
```

The gate verified MCP open, duplicate-open rejection, save, close, reopen,
cleanup after success, and cleanup after an injected test failure. Logic had no
document open afterward, the connector-owned Test Projects directory was
empty, and the source fixture's modification time and size were unchanged.

Acceptance diagnosis also hardened two real-runtime seams: lifecycle commands
now dispatch Apple Events without waiting for Logic's sometimes-blocked reply
and verify identity structurally through Accessibility, and variable-length
CoreMIDI packet lists are copied from their original callback storage.
If an asynchronous open misses its postcondition deadline, the connector now
retains the workspace and refuses cleanup until that exact delayed document can
be observed and closed; it never deletes a path that Logic may still open.
