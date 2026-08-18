import AppKit
import Foundation
import Testing

@testable import LogicBridgeCore

@Test("real Logic focus loss and emergency stop are observed", .enabled(if: ProcessInfo.processInfo.environment["LOGIC_INTEGRATION_TEST"] == "1"))
func realLogicFocusLossAndEmergencyStopAreObserved() async throws {
    let logicBundleIdentifier = "com.apple.logic10"
    let runningLogic = try #require(
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == logicBundleIdentifier
        }
    )
    let previouslyFrontmost = NSWorkspace.shared.frontmostApplication
    defer {
        previouslyFrontmost?.activate()
    }

    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == logicBundleIdentifier {
        let finder = try #require(
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        )
        #expect(finder.activate())
        try await waitForFrontmostApplication(otherThan: logicBundleIdentifier)
    }
    #expect(!runningLogic.isTerminated)

    let controller = ExclusiveTestModeController()
    try controller.activate(
        duration: 60,
        readiness: ExclusiveTestModeReadiness(
            accessibilityReady: AXIsProcessTrusted(),
            testProjectPolicyContext: true
        )
    )
    let monitor = AutomationSafetyMonitor(
        controller: controller,
        observer: MacAutomationSafetyObserver(humanInputRecency: 0)
    )

    monitor.poll()
    #expect(controller.snapshot.phase == .paused)
    #expect(controller.snapshot.pauseReason == .focusLost)

    controller.emergencyStop()
    #expect(controller.snapshot.phase == .inactive)
    #expect(controller.snapshot.stopReason == .emergencyStop)
}

private func waitForFrontmostApplication(otherThan bundleIdentifier: String) async throws {
    for _ in 0..<20 {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundleIdentifier {
            return
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("Could not move focus away from Logic Pro")
}
