# Handoff — 2026-08-18

## Repository state

- Repository: `cotyledonlab/logic-llm-connector` (private)
- Branch: `main`
- Last completed implementation commit: `6315bab`
- Last completed acceptance commit: `05228b1`
- Specification: [`SPEC.md`](SPEC.md)
- Delivery status: [`docs/tickets/README.md`](docs/tickets/README.md)
- Expected worktree state after this handoff commit: clean and pushed

## Completed tickets

- 0001 — versioned evidence-bearing native bridge contract
- 0002 — public `logic_doctor` MCP tool
- 0003 — native Doctor observations
- 0004 — complete MCP-to-Swift real-Logic tracer bullet
- 0005 — certificate-signed Companion app with stable bundle identity
- 0006 — permission readiness and restricted Accessibility inspection
- 0006b — visible status and Exclusive Test Mode safety state

Ticket 0006 was deliberately split after its tracer bullet proved that AX
inspection and mutable automation safety are separate vertical slices.

### Exclusive Test Mode

The Companion now runs as a menu-bar app and visibly reports native connection,
Logic running state, and automation state. The safety controller:

- defaults to inactive after every launch
- requires Accessibility readiness and a Test Project policy context
- bounds activation to at most one hour and expires automatically
- blocks new UI operations while paused
- cancels registered pending work on environmental interruption or emergency stop
- observes Logic focus loss, unexpected modal windows, and recent keyboard or
  mouse-button input

The menu uses a persistent red `TEST` label with a countdown while active and an
orange `PAUSED` label with the reason after an interruption. Starting Test Mode
is intentionally unavailable until ticket 0010 supplies a verified Test Project
policy context.

## Current verified capabilities

### `logic_doctor`

Available by default. It observes:

- macOS version and architecture
- Logic Pro installation, bundle, version, build, and running state
- Accessibility trust and remediation

### `logic_inspect_ui`

Absent by default. It is registered only when the MCP server starts with
`LOGIC_ENABLE_DIAGNOSTICS=1`, and the Companion independently rejects it unless
started with the same flag.

The result is bounded by `maxDepth` (0–8) and `maxNodes` (1–1000). Nodes contain
role, subrole, identifier, enabled/focused flags, parent, and child count. The
model cannot contain titles, values, descriptions, or UI actions.

## Verified local environment

- macOS: 26.5.2
- Architecture: arm64
- Logic Pro: 12.3, build 6674
- Logic bundle: `com.apple.logic10`
- Logic running during the final acceptance test: yes
- Packaged Companion Accessibility trust: granted
- Companion bundle ID: `dev.cotyledonlab.logic-llm-connector.companion`
- Signing authority: `Apple Development: jm547ster@gmail.com (ZMR8R9BPJK)`
- Actual signing TeamIdentifier: `4N63MQVR2B`
- Designated requirement: certificate-backed, not code-hash-backed

No Logic mutation has occurred. All real-Logic work to date is read-only.

## Final passing gates

Run from the repository root:

```sh
npm run typecheck
npm run build
npm test
npm run test:package
npm run test:integration
```

The final run passed:

- 5 JSON Schema contract tests
- 2 MCP client tests
- 13 discovered Swift tests, with 3 real-Logic-only cases skipped in the
  ordinary native suite
- certificate-backed package identity test
- packaged, full-stack real-Logic integration tests covering Doctor, default
  diagnostic denial, diagnostic opt-in, bounded AX inspection, focus loss, and
  emergency stop

`npm run test:integration` sets `LOGIC_INTEGRATION_TEST=1` and exercises the
running Logic installation through the packaged Companion.

## Next ticket

Start [`0007 — Create the virtual MIDI endpoint`](docs/tickets/0007-virtual-midi-endpoint.md).

Recommended first red→green slice:

1. Add a deterministic Swift test for stable virtual MIDI endpoint names and
   identity metadata.
2. Implement the smallest CoreMIDI owner that creates a source and destination
   without performing Logic UI onboarding.
3. Add a non-blocking receive handoff and loopback test.
4. Surface protocol/version compatibility through Doctor before beginning
   Mackie onboarding.

Ticket 0008 (Mackie onboarding) follows 0007. Ticket 0010 (Test Project
lifecycle) will supply the policy context that enables Test Mode activation.

## Important implementation facts

- TypeScript owns MCP; Swift owns macOS/Logic integration.
- The native seam is JSON-RPC 2.0 over a mode-`0600` Unix socket.
- Both processes default to `/tmp/logic-llm-connector-<uid>.sock`.
- The app build is `build/Logic Companion.app`; `build/` is gitignored.
- `scripts/build-companion-app.sh` defaults to this Mac's Apple Development
  signing identity. Override with `LOGIC_COMPANION_SIGNING_IDENTITY` elsewhere.
- The current Unix socket server processes one request per connection
  sequentially. This is adequate for read-only diagnostics but cancellation and
  concurrent operation handling remain future work.
- `ExclusiveTestModeController` is the stable safety gate for future mutating
  adapters. Register pending-operation cancellation before dispatching UI work.
- `AutomationSafetyMonitor` polls only while Test Mode is active; AppKit renders
  snapshots but does not own safety transitions.
- Native socket failures currently return a generic JSON-RPC internal error;
  structured native error mapping is still needed.
- UI text is intentionally excluded from the diagnostic snapshot. Project
  identity belongs in the later Test Project lifecycle Capability rather than a
  general AX dump.

## Do not do next

- Do not perform Mackie UI onboarding as part of ticket 0007; create and verify
  the CoreMIDI endpoints first.
- Do not mutate the currently open Logic project.
- Do not add arbitrary AX actions to `logic_inspect_ui`.
- Do not replace certificate signing with ad-hoc signing; ad-hoc designated
  requirements are tied to the changing code hash and destabilize permissions.
