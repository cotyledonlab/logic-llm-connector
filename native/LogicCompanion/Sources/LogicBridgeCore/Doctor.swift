import Foundation

public struct LogicApplicationObservation: Sendable, Equatable {
    public let installed: Bool
    public let running: Bool
    public let version: String?
    public let build: String?
    public let bundleIdentifier: String
    public let path: String

    public init(
        installed: Bool,
        running: Bool,
        version: String?,
        build: String?,
        bundleIdentifier: String,
        path: String
    ) {
        self.installed = installed
        self.running = running
        self.version = version
        self.build = build
        self.bundleIdentifier = bundleIdentifier
        self.path = path
    }
}

public protocol SystemObserving: Sendable {
    var macOSVersion: String { get }
    var architecture: String { get }
    var logicApplication: LogicApplicationObservation { get }
    var accessibilityTrusted: Bool { get }
}

public struct Doctor: Sendable {
    private let system: any SystemObserving
    private let midiEndpoints: (any VirtualMIDIEndpointObserving)?
    private let mackieControl: (any MackieControlConfigurationObserving)?
    private let now: @Sendable () -> Date

    public init(
        system: any SystemObserving,
        midiEndpoints: (any VirtualMIDIEndpointObserving)? = nil,
        mackieControl: (any MackieControlConfigurationObserving)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.system = system
        self.midiEndpoints = midiEndpoints
        self.mackieControl = mackieControl
        self.now = now
    }

    public func run(operationID: String) -> DoctorResult {
        let startedAt = now()
        let logic = system.logicApplication
        let systemEvidence = Evidence(
            source: "ProcessInfo",
            observedAt: startedAt,
            value: .object([
                "macOSVersion": .string(system.macOSVersion),
                "architecture": .string(system.architecture),
            ])
        )
        let logicEvidence = Evidence(
            source: "NSWorkspace",
            observedAt: startedAt,
            value: .object([
                "installed": .bool(logic.installed),
                "running": .bool(logic.running),
                "version": logic.version.map(JSONValue.string) ?? .null,
                "build": logic.build.map(JSONValue.string) ?? .null,
                "bundleIdentifier": .string(logic.bundleIdentifier),
                "path": .string(logic.path),
            ])
        )
        let permissionEvidence = Evidence(
            source: "AXIsProcessTrusted",
            observedAt: startedAt,
            value: .bool(system.accessibilityTrusted)
        )
        let logicName = logic.version.map { "Logic Pro \($0)" } ?? "Logic Pro"
        let logicStatus: CheckStatus = logic.installed ? .passed : .failed
        let logicSummary = logic.installed
            ? "\(logicName) is installed and \(logic.running ? "running" : "not running")"
            : "Logic Pro is not installed at \(logic.path)"

        var checks = [
            DoctorCheck(
                id: "system.macos",
                status: .passed,
                summary: "macOS \(system.macOSVersion) on \(system.architecture)",
                evidence: [systemEvidence]
            ),
            DoctorCheck(
                id: "logic.application",
                status: logicStatus,
                summary: logicSummary,
                remediation: logic.installed ? nil : "Install Logic Pro in /Applications.",
                evidence: [logicEvidence]
            ),
            DoctorCheck(
                id: "permission.accessibility",
                status: system.accessibilityTrusted ? .passed : .warning,
                summary: system.accessibilityTrusted
                    ? "Accessibility permission is granted"
                    : "Accessibility permission is not granted",
                remediation: system.accessibilityTrusted
                    ? nil
                    : "Allow Logic Companion in System Settings > Privacy & Security > Accessibility.",
                evidence: [permissionEvidence]
            ),
        ]
        var evidence = [systemEvidence, logicEvidence, permissionEvidence]

        if let midi = midiEndpoints?.snapshot {
            let midiEvidence = Evidence(
                source: "CoreMIDI",
                observedAt: startedAt,
                value: .object([
                    "protocol": .string(
                        midi.protocolID == ._1_0 ? "MIDI 1.0 UMP" : "MIDI 2.0 UMP"
                    ),
                    "source": .object([
                        "name": .string(VirtualMIDIEndpointIdentity.source.name),
                        "uniqueId": .number(Double(VirtualMIDIEndpointIdentity.source.uniqueID)),
                        "available": .bool(midi.sourceAvailable),
                    ]),
                    "destination": .object([
                        "name": .string(VirtualMIDIEndpointIdentity.destination.name),
                        "uniqueId": .number(Double(VirtualMIDIEndpointIdentity.destination.uniqueID)),
                        "available": .bool(midi.destinationAvailable),
                    ]),
                ])
            )
            let endpointsAvailable = midi.sourceAvailable && midi.destinationAvailable
            checks.append(
                DoctorCheck(
                    id: "midi.virtual_endpoints",
                    status: endpointsAvailable ? .passed : .warning,
                    summary: endpointsAvailable
                        ? "CoreMIDI MIDI 1.0 source and destination are available"
                        : "One or more CoreMIDI MIDI 1.0 virtual endpoints are unavailable",
                    remediation: endpointsAvailable
                        ? nil
                        : "Keep Logic Companion running while it recreates the virtual MIDI endpoints.",
                    evidence: [midiEvidence]
                )
            )
            evidence.append(midiEvidence)
        }

        if let configuration = mackieControl?.configuration {
            let assignmentValues = configuration.assignments.map { assignment in
                JSONValue.object([
                    "model": .string(assignment.model),
                    "inputPort": assignment.inputPort.map(JSONValue.string) ?? .null,
                    "outputPort": assignment.outputPort.map(JSONValue.string) ?? .null,
                ])
            }
            let mackieEvidence = Evidence(
                source: "Logic Pro Control Surfaces Setup",
                observedAt: startedAt,
                value: .object([
                    "state": .string(configuration.state.rawValue),
                    "expectedModel": .string(MackieControlConfigurationClassifier.expectedModel),
                    "expectedInputPort": .string(MackieControlConfigurationClassifier.expectedInputPort),
                    "expectedOutputPort": .string(MackieControlConfigurationClassifier.expectedOutputPort),
                    "assignments": .array(assignmentValues),
                ])
            )
            let presentation = Self.presentation(for: configuration.state)
            checks.append(
                DoctorCheck(
                    id: "logic.control_surface.mackie",
                    status: presentation.status,
                    summary: presentation.summary,
                    remediation: presentation.remediation,
                    evidence: [mackieEvidence]
                )
            )
            evidence.append(mackieEvidence)
        }

        return DoctorResult(
            protocolVersion: bridgeProtocolVersion,
            operationID: operationID,
            status: .succeeded,
            reliability: .verifiedDeterministic,
            startedAt: startedAt,
            finishedAt: now(),
            data: DoctorData(checks: checks),
            evidence: evidence
        )
    }

    private static func presentation(
        for state: MackieControlConfigurationState
    ) -> (status: CheckStatus, summary: String, remediation: String?) {
        switch state {
        case .missing:
            return (
                .warning,
                "The Logic LLM Connector Mackie Control is not configured",
                "Follow the Mackie Control setup guide while Logic Companion is running."
            )
        case .configured:
            return (
                .passed,
                "Mackie Control is assigned to both Logic LLM Connector MIDI ports",
                nil
            )
        case .conflicting:
            return (
                .failed,
                "Logic LLM Connector MIDI ports have conflicting control-surface assignments",
                "Remove assignments that split, duplicate, or use the connector ports with a non-Mackie model, then follow the setup guide."
            )
        }
    }
}
