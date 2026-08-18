# Architecture

## Deep modules and seams

The connector has three deliberately small interfaces:

1. **MCP interface** — semantic tools and resources used by an LLM client.
2. **Bridge interface** — versioned JSON-RPC between TypeScript and Swift.
3. **Logic operation interface** — capability outcomes with evidence,
   reliability, and recovery information.

The MCP module hides tool validation, deadlines, cancellation, orchestration,
and concise result formatting. The companion module hides Accessibility,
CoreMIDI, Apple Events, focus management, verification, and retries. Callers do
not choose an adapter.

## Invariants

- Successful operations contain verification evidence.
- Observed, inferred, requested, and unknown state remain distinguishable.
- Every mutation has an operation ID and bounded deadline.
- UI-driven work requires exclusive test mode and an emergency stop.
- Real-Logic tests mutate disposable project copies only.
- Direct `.logicx` mutation and reverse-engineered Logic Remote protocols are
  not trusted adapters.

## Confirmed test seams

- Validate bridge messages against the committed JSON Schema.
- Exercise MCP behavior through MCP tools and resources.
- Exercise the companion through its local bridge interface.
- Verify supported Logic capabilities against a running Logic installation.
- Exercise Exclusive Test Mode through its thread-safe controller and injected
  expiration scheduler; AppKit remains a presentation adapter.

Tests do not reach into private implementation details behind these seams.

## Delivery slices

The executable plan, acceptance criteria, and current status live in
[`docs/tickets`](tickets/README.md). The sequence below is the architecture-level
roadmap rather than a second status tracker.

1. Foundation, bridge contract, companion skeleton, and doctor
2. Logic discovery, permissions, test safety, AX inspection, and visible
   Exclusive Test Mode
3. Virtual Mackie Control onboarding and verified transport
4. Disposable-project lifecycle
5. Track creation and verified selection
6. MIDI regions, editing, playback, and bounce
7. Mixer, routing, plugins, automation, and editor coverage
