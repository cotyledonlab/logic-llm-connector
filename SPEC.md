# Logic LLM Connector Specification

Status: Accepted
Date: 2026-08-18
Initial target: Logic Pro 12.3 on John's Apple Silicon Mac, English UI

## 1. Product statement

Logic LLM Connector gives an LLM broad, verified, programmatic control of a
running Logic Pro session. It exposes a curated semantic MCP interface while a
local Companion selects among Logic integration mechanisms, observes outcomes,
and reports the limits of the current environment honestly.

The north star is an autonomous producer agent that can inspect a project,
plan work, edit and arrange material, configure instruments and effects,
audition results, recover from failures, save safely, and produce exports.

## 2. Goals

- Maximize the useful Logic Capabilities available to an LLM.
- Prefer semantic music-production Operations over UI-shaped primitives.
- Verify every mutation when Logic exposes an observable postcondition.
- Distinguish observed, inferred, requested, and unknown State Claims.
- Allow configurable autonomy without risking user projects by default.
- Discover compatibility and readiness at runtime.
- Add coverage through tested vertical slices against real Logic Pro.
- Keep Logic adapter selection and recovery behavior out of MCP callers.

## 3. Hard constraints and non-goals

- Logic Pro has no comprehensive public track, region, mixer, plugin, or
  transport object model.
- Perfectly headless, transactional, version-independent control is not
  achievable with supported interfaces.
- Direct mutation of `.logicx` internals is not a trusted implementation path.
- Reverse-engineered Logic Remote protocols are not a foundation for trusted
  Operations.
- Version one targets the exact local environment before generalizing to other
  Logic versions, languages, layouts, and Macs.
- The connector supplies deterministic musical representations and transforms;
  artistic judgment remains with the calling LLM.

## 4. Users and operating modes

### 4.1 Primary user

An LLM acting as an autonomous producer through an MCP client, supervised by a
human who owns the Mac and Logic projects.

### 4.2 Autonomy levels

The runtime must support policy-selected autonomy levels:

1. Read-only: observations and diagnostics only.
2. Reversible: reads plus reversible edits without per-Operation confirmation.
3. Confirmed-risk: save, overwrite, delete, close, bounce, plugin installation,
   and external-file Operations require confirmation.
4. Test mode: broad mutation is allowed only inside a Test Project under
   Exclusive Test Mode.

The default is reversible access with confirmation for destructive or
externally visible Operations.

## 5. Runtime architecture

### 5.1 MCP module

The TypeScript MCP module owns:

- MCP 2026-07-28 protocol support over standard input/output initially
- semantic tool and resource schemas
- input validation and policy enforcement
- operation IDs, deadlines, cancellation, and concise client results
- orchestration across multi-step semantic Operations
- capability discovery and compatibility presentation

Streamable HTTP is deferred until remote or multi-client access is required.

### 5.2 Companion module

The signed Swift Companion owns:

- macOS and Logic discovery
- Accessibility inspection and UI-driven Operations
- focus, modal-dialog, keyboard, and mouse safety
- CoreMIDI virtual endpoints and control-surface feedback
- Apple Event document lifecycle Operations
- native observations, retries, and postcondition verification
- connection status, permissions, pause, and emergency stop

The Companion has a stable bundle identity so macOS permissions survive normal
development and installation workflows.

### 5.3 Native seam

The MCP module and Companion communicate using versioned JSON-RPC 2.0 over a
mode-`0600` Unix domain socket. Committed JSON Schemas define requests,
responses, events, errors, Capability Profiles, Reliability, and Evidence.

Every mutation request will eventually carry:

- protocol version
- transport request ID
- operation ID
- deadline
- cancellation identity
- preconditions
- safety classification
- parameters

Every outcome carries:

- operation ID and final status
- Reliability
- start and finish timestamps
- structured result data
- Evidence
- partial effects and recovery guidance when applicable

## 6. Logic adapters

The Companion selects adapters; MCP callers do not.

### 6.1 CoreMIDI control surface

A virtual Mackie Control-compatible endpoint is the preferred documented live
control and feedback plane for transport, channel strips, mixer values,
automation modes, markers, sends, routing, and plugin parameters it exposes.

### 6.2 Accessibility and key commands

Accessibility inspection, UI actions, and Logic key commands provide broad
coverage for Operations unavailable through the control surface. UI-driven
Operations must declare contextual assumptions and verify postconditions.

Initial UI compatibility is English Logic Pro 12.3, a known workspace layout,
standard display scaling, and no simultaneous human input.

### 6.3 Apple Events

Apple Events are limited to document and application lifecycle behavior that
Logic actually exposes, such as open, save, close, and quit. They are not a DAW
object model.

### 6.4 Supported interchange

Standard MIDI, audio, AAF, XML, MusicXML, and other documented formats may be
used for bulk creation or exchange where they preserve the required semantics.
Lossy interchange must be explicit in the result.

### 6.5 Later plugin-side adapters

Scripter or Audio Units may later support in-session MIDI or audio generation.
They do not replace project-level Logic control and are not required for the
initial transport and editing slices.

## 7. MCP interface

### 7.1 Tool layers

The public interface has three layers:

1. Semantic tools, such as creating a software-instrument track or arranging a
   MIDI passage.
2. Composable primitives, such as setting a channel-strip parameter.
3. Restricted diagnostic escape hatches, such as inspecting the Accessibility
   tree or invoking an allowlisted key command.

Diagnostic escape hatches are disabled by default for ordinary agents. The MCP
server must avoid publishing hundreds of shallow UI-shaped tools.

### 7.2 Resources

Structured resources expose Capability Profiles, observed project/session
state, operation traces, and supported semantic vocabularies when resources are
more suitable than tool calls.

### 7.3 Initial tools

- `logic_doctor`: read-only readiness and remediation
- `logic_capabilities`: current Capability Profile and supported Operations
- `logic_inspect_ui`: restricted, read-only Accessibility snapshot
- transport tools: play, stop, locate, cycle, record readiness
- project lifecycle tools: open Test Project, save, close, reopen

Later tickets add tracks, regions, MIDI, audio, mixer, routing, plugins,
automation, editors, markers, tempo, recording, import, export, bounce, undo,
and recovery tools.

## 8. State, evidence, and reliability

### 8.1 State Claims

Every reported fact is classified as:

- observed: directly read from Logic or its runtime
- inferred: derived from Observations but not directly exposed
- requested: the state an Operation attempted to establish
- unknown: unavailable or ambiguous

Requested or inferred state must never be presented as observed.

### 8.2 Reliability classes

- `verified_deterministic`: a documented mechanism and deterministic
  postcondition Observation agree.
- `verified_ui_driven`: a contextual UI action completed and its postcondition
  was observed.
- `best_effort`: dispatch occurred but full verification was impossible.
- `unsupported`: the current Capability Profile cannot perform the Operation.

### 8.3 Supported Capability rule

A Capability is supported only when it has:

- a stable semantic contract
- runtime capability detection
- an explicit safety classification
- at least one adapter
- postcondition verification
- recovery behavior
- unit and cross-language contract coverage
- a passing real-Logic integration test
- user documentation

## 9. Safety

- Mutating integration tests may target only Test Projects in a dedicated test
  directory.
- A user project used as a fixture must be copied before Logic opens it.
- UI-driven tests require Exclusive Test Mode.
- Exclusive Test Mode must visibly indicate automation, expose pause and
  emergency stop, enforce timeouts, and clean up after success or failure.
- The runtime must detect unexpected modals, focus loss, project identity
  changes, and simultaneous human input where practical.
- Save, overwrite, delete, close, quit, bounce, plugin installation, and
  external-file Operations are policy-gated.
- Diagnostic primitives are allowlisted and disabled by default.

## 10. Capability Profile

`logic_doctor` and `logic_capabilities` observe at least:

- macOS version and architecture
- Logic Pro path, bundle identifier, version, build, and running state
- UI language and relevant display/workspace assumptions
- Companion identity and protocol compatibility
- Accessibility and Apple Events permissions
- virtual MIDI endpoints and control-surface installation
- Exclusive Test Mode readiness
- current project identity when observable
- installed plugins when that discovery becomes available

Unsupported or unverified combinations must fail explicitly rather than
attempting brittle automation silently.

## 11. Observability and recovery

Each integration Operation records a scrubbed trace containing:

- timestamps and duration
- selected adapter
- preconditions
- commands dispatched
- Observations and Evidence
- retries and timeout decisions
- partial effects
- recovery guidance
- failure artifacts such as an Accessibility snapshot or screenshot when safe

User-facing MCP results remain concise. Full traces are available for diagnosis
without leaking unrelated project content or secrets.

## 12. Verification strategy

### 12.1 Test seams

1. JSON Schema contract validation
2. MCP tools and resources through a real MCP client
3. Companion behavior through the local native seam
4. Cross-language contract fixtures
5. Real Logic Pro acceptance tests

Tests exercise public interfaces, not private implementation details.

### 12.2 Gates

- TypeScript and Swift tests pass.
- Cross-language bridge tests pass.
- MCP protocol behavior passes the official MCP Inspector or equivalent SDK
  client tests.
- Relevant real-Logic tests pass under the current Capability Profile.
- Mutating tests prove cleanup on both success and failure.

### 12.3 Delivery discipline

Each vertical slice follows red → green, then receives review, documentation, a
clear commit, and a push before the next slice begins. A Capability may not be
advertised as supported before its real-Logic acceptance gate passes.

## 13. Delivery sequence

1. Foundation: repository, schemas, MCP skeleton, Companion, Doctor
2. Companion packaging, permissions, test safety, Accessibility inspection
3. CoreMIDI virtual endpoint and Mackie Control onboarding
4. Verified transport
5. Test Project open, save, close, and reopen
6. Track creation and verified selection
7. MIDI region creation, editing, playback, and bounce
8. Mixer, routing, plugins, and automation
9. Editors, recording, advanced import/export, and remaining coverage

The tickets in `docs/tickets/` are the executable plan and source of current
status for this sequence.

## 14. First integrated milestone

The initial end-to-end acceptance path must:

1. diagnose the environment
2. connect an MCP client through the stdio server to the Companion
3. open a disposable project fixture
4. establish the virtual control surface
5. start and stop playback
6. observe and verify transport feedback
7. save, close, reopen, and verify project identity
8. leave Logic and the test directory in a known state after success or failure

Steps 1 and 2 are complete. Remaining steps are split into the ordered tickets.

## 15. Completion criteria

The project reaches its first fully featured release when the supported action
catalog covers the common end-to-end production workflow—project lifecycle,
transport, tracks, regions, MIDI, audio, mixer, routing, plugins, automation,
markers and tempo, recording, import/export, bounce, undo, and recovery—and
every advertised Capability satisfies the Supported Capability rule.

“Maximum actions” remains an expanding coverage target rather than a claim of
perfect control over undocumented Logic internals.
