# 0006b — Add visible status and Exclusive Test Mode

Status: Pending
Depends on: 0006

## Outcome

The Companion visibly reports connection and automation state, and all future
UI mutations are gated by an interruptible Exclusive Test Mode.

## Scope

- Menu-bar connection and Logic status
- Exclusive Test Mode indicator and bounded duration
- Pause, resume, emergency stop, and automatic timeout
- Observation of focus loss, unexpected modals, and simultaneous human input
  where practical
- Stable safety-state interface for later mutating adapters

## Acceptance criteria

- Test Mode cannot activate without Accessibility readiness and a Test Project
  policy context.
- Active automation is continuously visible.
- Pause prevents new UI actions; emergency stop cancels pending work and leaves
  Test Mode.
- Test Mode expires automatically and defaults to inactive after relaunch.
- State transitions have deterministic Swift tests.
- A real-Logic test proves focus loss and emergency stop are observed without
  mutating the open project.
