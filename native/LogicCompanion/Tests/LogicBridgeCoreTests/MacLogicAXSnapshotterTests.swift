import Foundation
import Testing

@testable import LogicBridgeCore

@Test(
    "running Logic exposes a bounded text-free Accessibility snapshot",
    .enabled(if: ProcessInfo.processInfo.environment["LOGIC_INTEGRATION_TEST"] == "1")
)
func runningLogicExposesBoundedAXSnapshot() throws {
    let limits = AXSnapshotLimits(maxDepth: 2, maxNodes: 100)
    let snapshot = try MacLogicAXSnapshotter().capture(limits: limits)

    #expect(snapshot.application.bundleIdentifier == "com.apple.logic10")
    #expect(snapshot.application.pid > 0)
    #expect(snapshot.limits == limits)
    #expect(!snapshot.nodes.isEmpty)
    #expect(snapshot.nodes.count <= 100)
    #expect(snapshot.nodes[0].id == "node-0")
    #expect(snapshot.nodes[0].parentID == nil)
    #expect(snapshot.nodes[0].role == "AXApplication")
}
