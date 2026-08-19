# Delivery tickets

Tickets are executed in numeric order unless their dependency list explicitly
allows parallel work. A ticket is complete only when every acceptance criterion
passes and the result is committed and pushed.

| Ticket | Status | Outcome |
|---|---|---|
| [0001](0001-bridge-contract.md) | Complete | Versioned evidence-bearing native contract |
| [0002](0002-mcp-doctor.md) | Complete | Public `logic_doctor` MCP tool |
| [0003](0003-native-doctor.md) | Complete | Native readiness observations |
| [0004](0004-full-stack-doctor.md) | Complete | Real-Logic MCP-to-Swift tracer bullet |
| [0005](0005-package-companion-app.md) | Complete | Signed Companion with stable identity |
| [0006](0006-test-safety-and-ax-inspection.md) | Complete | Permission and safe AX snapshot |
| [0006b](0006b-exclusive-test-mode.md) | Complete | Visible status and Exclusive Test Mode |
| [0007](0007-virtual-midi-endpoint.md) | Complete | Persistent CoreMIDI virtual endpoint |
| [0008](0008-mackie-onboarding.md) | Complete | Repeatable Logic control-surface setup |
| [0009](0009-verified-transport.md) | In Progress | Play/stop/location with feedback |
| [0010](0010-test-project-lifecycle.md) | Pending | Safe open/save/close/reopen |
| [0011](0011-track-operations.md) | Pending | Track creation and selection |
| [0012](0012-midi-region-operations.md) | Pending | MIDI creation and editing |
| [0013](0013-audio-and-recording.md) | Pending | Audio regions and recording |
| [0014](0014-mixer-and-routing.md) | Pending | Mixer, sends, buses, and I/O |
| [0015](0015-plugins-and-automation.md) | Pending | Plugins, parameters, and automation |
| [0016](0016-arrangement-and-editors.md) | Pending | Global tracks, editors, and arrangement |
| [0017](0017-import-export-and-bounce.md) | Pending | Supported exchange and deliverables |
| [0018](0018-coverage-hardening.md) | Pending | Capability audit and first release |

## Existing commit map

- `ea191f3` and `f2a0b12` → ticket 0001
- `773b963` → ticket 0002
- `da5aad5` → ticket 0003
- `b1644cd` → ticket 0004
- `d0143b3`, `b17666b`, `ca0bb09`, and `07d51a7` → ticket 0007
- `cfbd6bc`, `1020ec6`, `5bd4749`, `4ce72d7`, `bc06cd9`, and `0ff2a21` → ticket 0008
- `d886546`, `4805724`, and `6a4a495` → ticket 0009 play/stop checkpoint
- `8b146e3`, `e9258f4`, `dfddb3a`, `85a4a2e`, `3ae6a02`, and `2e11de0`
  → ticket 0009 location investigation
