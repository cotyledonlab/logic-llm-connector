# Logic Automation

Logic Automation describes verified work requested by an LLM and carried out
against a specific, running Logic Pro environment.

## Language

**Capability**:
A Logic behavior the connector can discover, classify, and attempt in the
current environment.
_Avoid_: Feature, command

**Operation**:
One bounded attempt to exercise a Capability, identified independently from
its transport request and carrying its own outcome.
_Avoid_: Call, command, action

**Observation**:
A time-stamped fact read directly from Logic Pro or its surrounding runtime.
_Avoid_: State, truth

**Evidence**:
The collection of Observations supporting an Operation outcome.
_Avoid_: Log, proof

**State Claim**:
A statement about Logic classified as observed, inferred, requested, or
unknown. Only an observed State Claim is itself an Observation.
_Avoid_: State

**Reliability**:
An Operation classification of verified deterministic, verified UI-driven,
best-effort, or unsupported in the current Capability Profile.
_Avoid_: Confidence, stability

**Capability Profile**:
The observed Logic Pro environment in which Capabilities are classified,
including compatibility and readiness constraints.
_Avoid_: Configuration, environment

**Companion**:
The trusted local participant that observes Logic Pro and performs Operations
on its behalf.
_Avoid_: Helper, daemon, bridge

**Doctor**:
The read-only Capability that reports Capability Profile readiness and
actionable remediation.
_Avoid_: Health check, diagnostics

**Test Project**:
A disposable Logic project that automation may mutate under exclusive test
mode.
_Avoid_: Fixture, sandbox

**Exclusive Test Mode**:
A visible, interruptible state in which automated UI input has sole control of
the interactive Mac and may mutate only Test Projects.
_Avoid_: Automation mode
