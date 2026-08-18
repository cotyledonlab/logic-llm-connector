# Require evidence for supported operations

An Operation is not considered supported merely because input was dispatched:
it must report postcondition Evidence or explicitly degrade to best-effort or
unsupported. Logic automation is frequently contextual and UI-driven, so this
rule prevents requested or inferred state from being misrepresented as an
observed result, at the cost of additional observation work for every
Capability.
