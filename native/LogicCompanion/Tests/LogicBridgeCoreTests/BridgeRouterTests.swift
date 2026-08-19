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

private struct FixedAXSnapshotter: LogicAXSnapshotting {
    func capture(limits: AXSnapshotLimits) throws -> AXSnapshotData {
        AXSnapshotData(
            application: AXApplicationSnapshot(
                bundleIdentifier: "com.apple.logic10",
                pid: 42
            ),
            capturedAt: Date(timeIntervalSince1970: 0),
            limits: limits,
            truncated: false,
            nodes: [
                AXNodeSnapshot(
                    id: "node-0",
                    parentID: nil,
                    role: "AXApplication",
                    subrole: nil,
                    identifier: nil,
                    enabled: true,
                    focused: false,
                    childCount: 1
                )
            ]
        )
    }
}

private struct FixedTransportController: TransportControlling {
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    func observe(operationID: String) -> TransportStateResult {
        TransportStateResult(
            protocolVersion: bridgeProtocolVersion,
            operationID: operationID,
            status: .succeeded,
            reliability: .verifiedDeterministic,
            startedAt: timestamp,
            finishedAt: timestamp,
            data: state(.stopped),
            evidence: evidence(.stopped)
        )
    }

    func setPlaying(
        _ playing: Bool,
        operationID: String,
        timeoutMilliseconds: Int
    ) -> TransportOperationResult {
        let requested: TransportPlayingState = playing ? .playing : .stopped
        return TransportOperationResult(
            protocolVersion: bridgeProtocolVersion,
            operationID: operationID,
            status: .succeeded,
            reliability: .verifiedDeterministic,
            startedAt: timestamp,
            finishedAt: timestamp,
            data: TransportOperationData(
                requestedState: requested,
                commandDispatched: true,
                state: state(requested)
            ),
            evidence: evidence(requested)
        )
    }

    func movePlayhead(
        _ direction: TransportMoveDirection,
        steps: Int,
        operationID: String,
        timeoutMilliseconds: Int
    ) -> TransportLocationOperationResult {
        TransportLocationOperationResult(
            protocolVersion: bridgeProtocolVersion,
            operationID: operationID,
            status: .succeeded,
            reliability: .verifiedDeterministic,
            startedAt: timestamp,
            finishedAt: timestamp,
            data: TransportLocationOperationData(
                requestedDirection: direction,
                steps: steps,
                commandDispatched: true,
                initialPosition: TransportPositionData(
                    display: "0000000100",
                    observedAt: timestamp
                ),
                position: TransportPositionData(
                    display: "0000000101",
                    observedAt: timestamp
                )
            ),
            evidence: [Evidence(
                source: "Mackie Control position feedback",
                observedAt: timestamp,
                value: .string("0000000101")
            )]
        )
    }

    func locate(
        _ target: TransportLocateTarget,
        operationID: String,
        timeoutMilliseconds: Int
    ) -> TransportLocateOperationResult {
        TransportLocateOperationResult(
            protocolVersion: bridgeProtocolVersion,
            operationID: operationID,
            status: .succeeded,
            reliability: .verifiedDeterministic,
            startedAt: timestamp,
            finishedAt: timestamp,
            data: TransportLocateOperationData(
                requestedTarget: target,
                commandDispatched: true,
                initialPosition: TransportPositionData(
                    display: "0000000101",
                    observedAt: timestamp
                ),
                position: TransportPositionData(
                    display: "0000000100",
                    observedAt: timestamp
                )
            ),
            evidence: [Evidence(
                source: "Mackie Control position feedback",
                observedAt: timestamp,
                value: .string("0000000100")
            )]
        )
    }

    private func state(_ playing: TransportPlayingState) -> TransportStateData {
        TransportStateData(
            playing: playing,
            cycle: .disabled,
            recordReady: .notReady,
            observedAt: timestamp
        )
    }

    private func evidence(_ playing: TransportPlayingState) -> [Evidence] {
        [Evidence(
            source: "Mackie Control feedback",
            observedAt: timestamp,
            value: .string(playing.rawValue)
        )]
    }
}

private struct FixedProjectLifecycleController: ProjectLifecycleControlling {
    let hasVerifiedPolicyContext = true

    func observe(operationID: String) -> ProjectLifecycleResult { make(.observe, operationID) }
    func openFixture(at path: String, operationID: String, timeoutMilliseconds: Int) -> ProjectLifecycleResult { make(.open, operationID) }
    func save(operationID: String, timeoutMilliseconds: Int) -> ProjectLifecycleResult { make(.save, operationID) }
    func close(operationID: String, timeoutMilliseconds: Int) -> ProjectLifecycleResult { make(.close, operationID, project: nil, policyContext: false) }
    func reopen(operationID: String, timeoutMilliseconds: Int) -> ProjectLifecycleResult { make(.reopen, operationID) }
    func cleanup(operationID: String, timeoutMilliseconds: Int) -> ProjectLifecycleResult { make(.cleanup, operationID, project: nil, policyContext: false) }

    private func make(
        _ action: ProjectLifecycleAction,
        _ operationID: String,
        project: LogicProjectIdentity? = LogicProjectIdentity(
            name: "Fixture",
            path: "/tmp/managed/Fixture.logicx",
            modified: false,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ),
        policyContext: Bool = true
    ) -> ProjectLifecycleResult {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        return ProjectLifecycleResult(
            protocolVersion: bridgeProtocolVersion,
            operationID: operationID,
            status: .succeeded,
            reliability: .verifiedDeterministic,
            startedAt: timestamp,
            finishedAt: timestamp,
            data: ProjectLifecycleData(
                action: action,
                commandDispatched: action != .observe,
                project: project,
                managedProjectPath: "/tmp/managed/Fixture.logicx",
                policyContext: policyContext,
                cleanupPerformed: action == .cleanup,
                failure: nil
            ),
            evidence: [Evidence(
                source: "Logic Apple Events document observation",
                observedAt: timestamp,
                value: .string(action.rawValue)
            )]
        )
    }
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

@Test("bridge denies UI inspection unless diagnostics are enabled")
func bridgeDeniesDisabledUIInspection() throws {
    let request = """
    {"jsonrpc":"2.0","id":"inspect-1","method":"logic.inspectUI","params":{"protocolVersion":"1.0.0","operationId":"inspect-1","maxDepth":2,"maxNodes":100}}
    """.data(using: .utf8)!
    let router = BridgeRouter(
        doctor: Doctor(system: RouterSystem()),
        axSnapshotter: FixedAXSnapshotter(),
        diagnosticsEnabled: false
    )

    #expect(throws: BridgeRouterError.diagnosticsDisabled) {
        try router.handle(request)
    }
}

@Test("bridge routes enabled UI inspection without text fields")
func bridgeRoutesEnabledUIInspection() throws {
    let request = """
    {"jsonrpc":"2.0","id":"inspect-1","method":"logic.inspectUI","params":{"protocolVersion":"1.0.0","operationId":"inspect-1","maxDepth":2,"maxNodes":100}}
    """.data(using: .utf8)!
    let router = BridgeRouter(
        doctor: Doctor(system: RouterSystem()),
        axSnapshotter: FixedAXSnapshotter(),
        diagnosticsEnabled: true
    )

    let responseData = try router.handle(request)
    let response = try #require(
        JSONSerialization.jsonObject(with: responseData) as? [String: Any]
    )
    let result = try #require(response["result"] as? [String: Any])
    let data = try #require(result["data"] as? [String: Any])
    let nodes = try #require(data["nodes"] as? [[String: Any]])
    let firstNode = try #require(nodes.first)

    #expect(result["operationId"] as? String == "inspect-1")
    #expect(firstNode["role"] as? String == "AXApplication")
    #expect(firstNode["title"] == nil)
    #expect(firstNode["value"] == nil)
    #expect(firstNode["description"] == nil)
}

@Test("bridge routes transport state and verified play requests")
func bridgeRoutesTransportRequests() throws {
    let router = BridgeRouter(
        doctor: Doctor(system: RouterSystem()),
        transport: FixedTransportController()
    )
    let stateRequest = """
    {"jsonrpc":"2.0","id":"state-1","method":"logic.transport.state","params":{"protocolVersion":"1.0.0","operationId":"state-1"}}
    """.data(using: .utf8)!
    let playRequest = """
    {"jsonrpc":"2.0","id":"play-1","method":"logic.transport.setPlaying","params":{"protocolVersion":"1.0.0","operationId":"play-1","playing":true,"timeoutMs":750}}
    """.data(using: .utf8)!
    let moveRequest = """
    {"jsonrpc":"2.0","id":"move-1","method":"logic.transport.movePlayhead","params":{"protocolVersion":"1.0.0","operationId":"move-1","direction":"forward","steps":1,"timeoutMs":750}}
    """.data(using: .utf8)!
    let locateRequest = """
    {"jsonrpc":"2.0","id":"locate-1","method":"logic.transport.locate","params":{"protocolVersion":"1.0.0","operationId":"locate-1","target":"project_start","timeoutMs":750}}
    """.data(using: .utf8)!

    let stateResponse = try #require(
        JSONSerialization.jsonObject(with: router.handle(stateRequest)) as? [String: Any]
    )
    let stateResult = try #require(stateResponse["result"] as? [String: Any])
    let state = try #require(stateResult["data"] as? [String: Any])
    #expect(state["playing"] as? String == "stopped")

    let playResponse = try #require(
        JSONSerialization.jsonObject(with: router.handle(playRequest)) as? [String: Any]
    )
    let playResult = try #require(playResponse["result"] as? [String: Any])
    let playData = try #require(playResult["data"] as? [String: Any])
    #expect(playResult["status"] as? String == "succeeded")
    #expect(playData["requestedState"] as? String == "playing")
    #expect(playData["commandDispatched"] as? Bool == true)

    let moveResponse = try #require(
        JSONSerialization.jsonObject(with: router.handle(moveRequest)) as? [String: Any]
    )
    let moveResult = try #require(moveResponse["result"] as? [String: Any])
    let moveData = try #require(moveResult["data"] as? [String: Any])
    let position = try #require(moveData["position"] as? [String: Any])
    #expect(moveResult["status"] as? String == "succeeded")
    #expect(moveData["requestedDirection"] as? String == "forward")
    #expect(moveData["steps"] as? Int == 1)
    #expect(position["display"] as? String == "0000000101")

    let locateResponse = try #require(
        JSONSerialization.jsonObject(with: router.handle(locateRequest)) as? [String: Any]
    )
    let locateResult = try #require(locateResponse["result"] as? [String: Any])
    let locateData = try #require(locateResult["data"] as? [String: Any])
    let locatedPosition = try #require(locateData["position"] as? [String: Any])
    #expect(locateResult["status"] as? String == "succeeded")
    #expect(locateData["requestedTarget"] as? String == "project_start")
    #expect(locatedPosition["display"] as? String == "0000000100")
}

@Test("bridge routes project lifecycle requests")
func bridgeRoutesProjectLifecycleRequests() throws {
    let router = BridgeRouter(
        doctor: Doctor(system: RouterSystem()),
        projectLifecycle: FixedProjectLifecycleController()
    )
    let requests = [
        """
        {"jsonrpc":"2.0","id":"state-1","method":"logic.project.state","params":{"protocolVersion":"1.0.0","operationId":"state-1"}}
        """,
        """
        {"jsonrpc":"2.0","id":"open-1","method":"logic.project.openFixture","params":{"protocolVersion":"1.0.0","operationId":"open-1","fixturePath":"/tmp/Fixture.logicx","timeoutMs":1000}}
        """,
        """
        {"jsonrpc":"2.0","id":"save-1","method":"logic.project.save","params":{"protocolVersion":"1.0.0","operationId":"save-1","timeoutMs":1000}}
        """,
        """
        {"jsonrpc":"2.0","id":"close-1","method":"logic.project.close","params":{"protocolVersion":"1.0.0","operationId":"close-1","timeoutMs":1000}}
        """,
        """
        {"jsonrpc":"2.0","id":"reopen-1","method":"logic.project.reopen","params":{"protocolVersion":"1.0.0","operationId":"reopen-1","timeoutMs":1000}}
        """,
        """
        {"jsonrpc":"2.0","id":"cleanup-1","method":"logic.project.cleanup","params":{"protocolVersion":"1.0.0","operationId":"cleanup-1","timeoutMs":1000}}
        """,
    ]
    let expected = ["observe", "open", "save", "close", "reopen", "cleanup"]

    for (request, action) in zip(requests, expected) {
        let response = try #require(
            JSONSerialization.jsonObject(with: router.handle(Data(request.utf8))) as? [String: Any]
        )
        let result = try #require(response["result"] as? [String: Any])
        let data = try #require(result["data"] as? [String: Any])
        #expect(data["action"] as? String == action)
        #expect(result["status"] as? String == "succeeded")
    }
}
