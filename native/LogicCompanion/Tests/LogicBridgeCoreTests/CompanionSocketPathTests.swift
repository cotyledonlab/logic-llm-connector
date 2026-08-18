import Testing

@testable import LogicBridgeCore

@Test("default socket path is stable and user-specific")
func defaultSocketPathIsStableAndUserSpecific() {
    #expect(
        CompanionSocketPath.default(userID: 501)
            == "/tmp/logic-llm-connector-501.sock"
    )
}
