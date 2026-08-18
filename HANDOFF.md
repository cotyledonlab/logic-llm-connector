# Handoff — 2026-08-18

## Repository state

- Repository: `cotyledonlab/logic-llm-connector` (private)
- Branch: `main`
- Last completed implementation commit: `ca0bb09`
- Last completed acceptance commit: `07d51a7`
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
- 0007 — stable, recoverable CoreMIDI virtual endpoints

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

### Virtual MIDI endpoints

The Companion now owns a CoreMIDI MIDI 1.0 virtual source and destination for
its full process lifetime:

- `Logic LLM Connector Out`, unique ID `0x4C4C4D01`
- `Logic LLM Connector In`, unique ID `0x4C4C4D02`

Both advertise `Cotyledon Lab` as manufacturer and
`Logic LLM Connector Control` as model. Timestamped UMP messages loop through
both directions. Destination callbacks only copy the bounded packet data before
handing it to a dedicated dispatch queue. Missing endpoints are observable,
recreated independently with their stable metadata, and retried by the
Companion's existing status cadence.

## Current verified capabilities

### `logic_doctor`

Available by default. It observes:

- macOS version and architecture
- Logic Pro installation, bundle, version, build, and running state
- Accessibility trust and remediation
- CoreMIDI MIDI 1.0 protocol compatibility and virtual endpoint readiness

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
- 17 discovered Swift tests, with 3 real-Logic-only cases skipped in the
  ordinary native suite
- certificate-backed package identity test
- packaged, full-stack real-Logic integration tests covering Doctor, default
  diagnostic denial, diagnostic opt-in, bounded AX inspection, MIDI endpoint
  readiness, focus loss, and emergency stop

`npm run test:integration` sets `LOGIC_INTEGRATION_TEST=1` and exercises the
running Logic installation through the packaged Companion.

## Next ticket

Start [`0008 — Onboard virtual Mackie Control`](docs/tickets/0008-mackie-onboarding.md).

Recommended first red→green slice:

1. Add a deterministic Doctor classification for missing, configured, and
   conflicting Mackie Control assignments.
2. Implement the smallest read-only Logic observer that detects the expected
   control surface without writing preference files.
3. Define a guided setup path for a clean Logic profile and keep it separate
   from the general Accessibility diagnostic snapshot.
4. Verify configuration through both specialized Logic UI observations and
   MIDI feedback before adding transport Operations.

Ticket 0009 (verified transport) follows 0008. Ticket 0010 (Test Project
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
- `VirtualMIDIEndpointOwner` is the stable CoreMIDI seam. It uses MIDI 1.0 UMP,
  preserves host timestamps, serializes endpoint access, and hands receive work
  off the CoreMIDI callback thread.
- The virtual endpoint unique IDs are persisted as source constants, not
  generated at runtime. Do not change them after Logic onboarding begins.
- Native socket failures currently return a generic JSON-RPC internal error;
  structured native error mapping is still needed.
- UI text is intentionally excluded from the diagnostic snapshot. Project
  identity belongs in the later Test Project lifecycle Capability rather than a
  general AX dump.

## Do not do next

- Do not write Logic preference files directly during Mackie onboarding.
- Do not send transport or mixer messages until the expected control surface is
  observed and MIDI feedback verifies it.
- Do not mutate the currently open Logic project.
- Do not add arbitrary AX actions to `logic_inspect_ui`.
- Do not replace certificate signing with ad-hoc signing; ad-hoc designated
  requirements are tied to the changing code hash and destabilize permissions.
