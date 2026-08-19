# 0010 — Implement Test Project lifecycle

Status: In progress — implementation complete; real-Logic acceptance pending
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
- Apple Events expose and verify front-document name, path, and modified state
  for open, save, close, and reopen.
- User documents, identity drift, unsaved close, Automation denial, and visible
  modal dialogs fail explicitly without treating dispatch as success.
- Cleanup closes only the matching managed copy without saving and removes only
  its connector-owned workspace. Unit and MCP tests cover cleanup after both a
  successful flow and an injected failure.
- A verified managed project enables Exclusive Test Mode. Losing that identity
  pauses automation and cancels pending UI work; resume revalidates the policy.

## Remaining acceptance

Run the opt-in packaged MCP-to-Logic lifecycle test with Logic showing no open
document and a saved disposable fixture:

```sh
LOGIC_PROJECT_INTEGRATION_TEST=1 \
LOGIC_TEST_PROJECT_FIXTURE="/absolute/path/to/Fixture.logicx" \
npm run test:integration
```

The 2026-08-19 acceptance attempt stopped before dispatch because the open user
project `LLM Jazz.logicx` had unsaved changes. It was not closed, saved, or
copied.
