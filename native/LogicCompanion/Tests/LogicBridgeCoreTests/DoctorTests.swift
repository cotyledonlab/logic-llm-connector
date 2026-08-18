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

@Test("doctor reports observed Logic and permission readiness")
func doctorReportsObservedReadiness() throws {
    let result = Doctor(system: FixedSystem()).run(operationID: "doctor-1")

    #expect(result.protocolVersion == "1.0.0")
    #expect(result.operationID == "doctor-1")
    #expect(result.status == .succeeded)
    #expect(result.reliability == .verifiedDeterministic)
    #expect(result.data.checks.map(\.id) == [
        "system.macos",
        "logic.application",
        "permission.accessibility",
    ])
    #expect(result.data.checks[1].status == .passed)
    #expect(result.data.checks[1].summary == "Logic Pro 12.3 is installed and running")
    #expect(result.data.checks[2].status == .warning)
    #expect(result.data.checks[2].remediation != nil)
    #expect(!result.evidence.isEmpty)

    let encoded = try JSONEncoder.bridge.encode(result)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["operationId"] as? String == "doctor-1")
    #expect(object["reliability"] as? String == "verified_deterministic")
}
