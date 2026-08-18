# Handoff — 2026-08-18

## Repository state

- Repository: `cotyledonlab/logic-llm-connector` (private)
- Branch: `main`
- Last completed implementation commit: `d66cca8`
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

Ticket 0006 was deliberately split after its tracer bullet proved that AX
inspection and mutable automation safety are separate vertical slices.

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
- 7 discovered Swift tests, with real-Logic-only cases skipped in the ordinary
  native suite
- certificate-backed package identity test
- packaged, full-stack real-Logic integration test covering Doctor, default
  diagnostic denial, diagnostic opt-in, and bounded AX inspection

`npm run test:integration` sets `LOGIC_INTEGRATION_TEST=1` and exercises the
running Logic installation through the packaged Companion.

## Next ticket

Start [`0006b — Add visible status and Exclusive Test Mode`](docs/tickets/0006b-exclusive-test-mode.md).

Recommended first red→green slice:

1. Add a deterministic Swift test for safety states: inactive → active with a
   deadline → paused → resumed → emergency-stopped.
2. Implement a thread-safe safety-state module with injected time.
3. Make the default after launch inactive and make expiration automatic.
4. Only then add the menu-bar adapter that renders connection, Logic, Test Mode,
   pause, and emergency-stop state.

Ticket 0008 (Mackie onboarding) and ticket 0010 (Test Project lifecycle) now
depend on 0006b because they will perform UI mutations.

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
- Native socket failures currently return a generic JSON-RPC internal error;
  structured native error mapping is still needed.
- UI text is intentionally excluded from the diagnostic snapshot. Project
  identity belongs in the later Test Project lifecycle Capability rather than a
  general AX dump.

## Do not do next

- Do not begin MIDI or Mackie UI onboarding before ticket 0006b is complete.
- Do not mutate the currently open Logic project.
- Do not add arbitrary AX actions to `logic_inspect_ui`.
- Do not replace certificate signing with ad-hoc signing; ad-hoc designated
  requirements are tied to the changing code hash and destabilize permissions.
