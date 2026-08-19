import AppKit
import ApplicationServices
import Foundation

public protocol AutomationSafetyObserving: Sendable {
    func currentInterruption() -> AutomationSafetyInterruption?
}

public struct AutomationSafetyMonitor: Sendable {
    private let controller: ExclusiveTestModeController
    private let observer: any AutomationSafetyObserving
    private let policyContextReady: @Sendable () -> Bool

    public init(
        controller: ExclusiveTestModeController,
        observer: any AutomationSafetyObserving,
        policyContextReady: @escaping @Sendable () -> Bool = { true }
    ) {
        self.controller = controller
        self.observer = observer
        self.policyContextReady = policyContextReady
    }

    public func poll() {
        guard controller.snapshot.phase == .active else { return }
        guard policyContextReady() else {
            controller.observe(.projectIdentityChanged)
            return
        }
        guard let interruption = observer.currentInterruption() else { return }
        controller.observe(interruption)
    }
}

public struct MacAutomationSafetyObserver: AutomationSafetyObserving {
    private let logicBundleIdentifier = "com.apple.logic10"
    private let humanInputRecency: TimeInterval

    public init(humanInputRecency: TimeInterval = 0.35) {
        self.humanInputRecency = humanInputRecency
    }

    public func currentInterruption() -> AutomationSafetyInterruption? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == logicBundleIdentifier else {
            return .focusLost
        }
        if logicHasModalWindow() {
            return .unexpectedModal
        }
        if hasRecentHumanInput() {
            return .humanInput
        }
        return nil
    }

    private func logicHasModalWindow() -> Bool {
        guard AXIsProcessTrusted(),
              let logic = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == logicBundleIdentifier
              }) else { return false }

        let application = AXUIElementCreateApplication(logic.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
        let windowValue else { return false }

        var modalValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            windowValue as! AXUIElement,
            kAXModalAttribute as CFString,
            &modalValue
        ) == .success else { return false }
        return (modalValue as? NSNumber)?.boolValue == true
    }

    private func hasRecentHumanInput() -> Bool {
        let eventTypes: [CGEventType] = [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
        ]
        return eventTypes.contains {
            CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: $0
            ) <= humanInputRecency
        }
    }
}
