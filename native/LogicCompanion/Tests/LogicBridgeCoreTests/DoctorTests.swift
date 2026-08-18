import Foundation
import Testing

@testable import LogicBridgeCore

private struct FixedSystem: SystemObserving {
    let macOSVersion = "15.6"
    let architecture = "arm64"
    let logicApplication = LogicApplicationObservation(
        installed: true,
        running: true,
        version: "12.3",
        build: "6674",
        bundleIdentifier: "com.apple.logic10",
        path: "/Applications/Logic Pro.app"
    )
    let accessibilityTrusted = false
}

private struct FixedMIDIEndpoints: VirtualMIDIEndpointObserving {
    let snapshot = VirtualMIDIEndpointSnapshot(
        sourceAvailable: true,
        destinationAvailable: true,
        protocolID: ._1_0
    )
}

private struct FixedMackieControl: MackieControlConfigurationObserving {
    let mackieControlObservation = MackieControlObservation.observed(MackieControlConfiguration(
        state: .configured,
        assignments: [
            ControlSurfaceAssignment(
                model: "Mackie Control",
                inputPort: "Logic LLM Connector Out",
                outputPort: "Logic LLM Connector In"
            ),
        ]
    ))
}

private struct FixedMackieFeedback: MackieControlFeedbackObserving {
    let feedbackSnapshot = MackieControlFeedbackSnapshot(
        packetCount: 2,
        midi1ChannelVoicePacketCount: 2,
        systemExclusivePacketCount: 0,
        lastReceivedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

@Test("doctor reports observed Logic and permission readiness")
func doctorReportsObservedReadiness() throws {
    let result = Doctor(
        system: FixedSystem(),
        midiEndpoints: FixedMIDIEndpoints(),
        mackieControl: FixedMackieControl(),
        mackieFeedback: FixedMackieFeedback()
    ).run(operationID: "doctor-1")

    #expect(result.protocolVersion == "1.0.0")
    #expect(result.operationID == "doctor-1")
    #expect(result.status == .succeeded)
    #expect(result.reliability == .verifiedDeterministic)
    #expect(result.data.checks.map(\.id) == [
        "system.macos",
        "logic.application",
        "permission.accessibility",
        "midi.virtual_endpoints",
        "logic.control_surface.mackie",
        "midi.mackie_feedback",
    ])
    #expect(result.data.checks[1].status == .passed)
    #expect(result.data.checks[1].summary == "Logic Pro 12.3 is installed and running")
    #expect(result.data.checks[2].status == .warning)
    #expect(result.data.checks[2].remediation != nil)
    #expect(result.data.checks[3].status == .passed)
    #expect(result.data.checks[3].summary == "CoreMIDI MIDI 1.0 source and destination are available")
    #expect(result.data.checks[3].evidence.first?.value == .object([
        "protocol": .string("MIDI 1.0 UMP"),
        "source": .object([
            "name": .string("Logic LLM Connector Out"),
            "uniqueId": .number(Double(0x4C4C_4D01)),
            "available": .bool(true),
        ]),
        "destination": .object([
            "name": .string("Logic LLM Connector In"),
            "uniqueId": .number(Double(0x4C4C_4D02)),
            "available": .bool(true),
        ]),
    ]))
    #expect(result.data.checks[4].status == .passed)
    #expect(result.data.checks[4].summary == "Mackie Control is assigned to both Logic LLM Connector MIDI ports")
    #expect(result.data.checks[4].evidence.first?.value == .object([
        "state": .string("configured"),
        "expectedModel": .string("Mackie Control"),
        "expectedInputPort": .string("Logic LLM Connector Out"),
        "expectedOutputPort": .string("Logic LLM Connector In"),
        "assignments": .array([
            .object([
                "model": .string("Mackie Control"),
                "inputPort": .string("Logic LLM Connector Out"),
                "outputPort": .string("Logic LLM Connector In"),
            ]),
        ]),
    ]))
    #expect(result.data.checks[5].status == .passed)
    #expect(result.data.checks[5].summary == "Logic sent Mackie-compatible feedback to the Companion")
    #expect(!result.evidence.isEmpty)

    let encoded = try JSONEncoder.bridge.encode(result)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["operationId"] as? String == "doctor-1")
    #expect(object["reliability"] as? String == "verified_deterministic")
}
