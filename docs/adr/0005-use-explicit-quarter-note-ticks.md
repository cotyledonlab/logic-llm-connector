# Use explicit quarter-note ticks for musical time

MIDI region locations and lengths use absolute integer ticks from project start,
while note onsets use integer ticks relative to their region; every value carries
an explicit pulses-per-quarter (`ppq`) timebase and the initial public contract
uses 960 PPQ. This avoids meter-dependent bar/beat strings and floating-point
rounding, maps exactly to Logic's 960-tick quarter-note grid, and still permits
lossless scaling to and from Standard MIDI Files with other time divisions.

## Consequences

Durations are represented by the same type but must be positive, locations must
be non-negative, and values at another PPQ must be scaled exactly or reported as
a Fidelity Difference rather than silently rounded. Bar counts are presentation
derived from the project's meter and are never the canonical storage format.
