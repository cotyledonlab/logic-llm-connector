import Foundation
import Testing

@testable import LogicBridgeCore

private struct RouterSystem: SystemObserving {
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
    let accessibilityTrusted = true
}

@Test("bridge routes a versioned JSON-RPC doctor request")
func bridgeRoutesDoctorRequest() throws {
    let request = """
    {"jsonrpc":"2.0","id":"request-1","method":"logic.doctor","params":{"protocolVersion":"1.0.0","operationId":"doctor-1"}}
    """.data(using: .utf8)!
    let router = BridgeRouter(doctor: Doctor(system: RouterSystem()))

    let responseData = try router.handle(request)
    let response = try #require(
        JSONSerialization.jsonObject(with: responseData) as? [String: Any]
    )
    let result = try #require(response["result"] as? [String: Any])

    #expect(response["jsonrpc"] as? String == "2.0")
    #expect(response["id"] as? String == "request-1")
    #expect(result["operationId"] as? String == "doctor-1")
    #expect(result["status"] as? String == "succeeded")
}
