# Domain language

- **Operation**: one requested Logic capability with an operation ID, deadline,
  preconditions, result, and evidence.
- **Observation**: state read directly from Logic, macOS, MIDI feedback, or the
  filesystem at a recorded time.
- **Evidence**: the source, time, and value supporting an operation result.
- **Reliability**: `verified_deterministic`, `verified_ui_driven`,
  `best_effort`, or `unsupported`.
- **Capability profile**: the observed macOS, Logic, language, display,
  permissions, control-surface, and plugin environment.
- **Companion**: the signed native macOS process that owns Logic-specific
  adapters.
- **Doctor**: the read-only operation that reports whether prerequisites are
  observable and ready, with remediation for failures.

Requested and inferred state must never be presented as observed state.
