import AppKit
import ApplicationServices
import Foundation

public struct ControlSurfaceUIElement: Sendable, Equatable {
    public let strings: [String]
    public let children: [ControlSurfaceUIElement]

    public init(strings: [String], children: [ControlSurfaceUIElement] = []) {
        self.strings = strings
        self.children = children
    }
}

public enum ControlSurfaceSetupParser {
    public static func assignments(
        in root: ControlSurfaceUIElement
    ) -> [ControlSurfaceAssignment]? {
        let flattened = flatten(root)
        guard !flattened.isEmpty else { return nil }

        var assignments: [ControlSurfaceAssignment] = []
        collectAssignments(in: root, into: &assignments)
        if !assignments.isEmpty { return assignments }

        let strings = flattened.map(normalize)
        guard strings.contains(where: isRelevantPort) else { return [] }
        return [assignment(from: strings)]
    }

    private static func collectAssignments(
        in node: ControlSurfaceUIElement,
        into assignments: inout [ControlSurfaceAssignment]
    ) {
        let strings = flatten(node).map(normalize)
        let containsRelevantPort = strings.contains(where: isRelevantPort)
        guard containsRelevantPort else { return }

        if node.strings.map(normalize).contains(where: isPossibleModel) {
            assignments.append(assignment(from: strings))
            return
        }

        let relevantChildren = node.children.filter {
            flatten($0).map(normalize).contains(where: isRelevantPort)
        }
        if relevantChildren.isEmpty {
            assignments.append(assignment(from: strings))
        } else {
            for child in relevantChildren {
                collectAssignments(in: child, into: &assignments)
            }
        }
    }

    private static func assignment(from strings: [String]) -> ControlSurfaceAssignment {
        ControlSurfaceAssignment(
            model: strings.first(where: isPossibleModel) ?? "Unknown",
            inputPort: strings.first(where: {
                $0 == MackieControlConfigurationClassifier.expectedInputPort
            }),
            outputPort: strings.first(where: {
                $0 == MackieControlConfigurationClassifier.expectedOutputPort
            })
        )
    }

    private static func flatten(_ node: ControlSurfaceUIElement) -> [String] {
        node.strings + node.children.flatMap(flatten)
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isRelevantPort(_ value: String) -> Bool {
        value == MackieControlConfigurationClassifier.expectedInputPort
            || value == MackieControlConfigurationClassifier.expectedOutputPort
    }

    private static func isPossibleModel(_ value: String) -> Bool {
        let ignored = [
            "Control Surface Setup",
            "Control Surfaces Setup",
            "Device",
            "Model",
            "Input Port",
            "Output Port",
            MackieControlConfigurationClassifier.expectedInputPort,
            MackieControlConfigurationClassifier.expectedOutputPort,
        ]
        return !value.isEmpty && !ignored.contains(value)
    }
}

public struct MacMackieControlObserver: MackieControlConfigurationObserving {
    private let bundleIdentifier = "com.apple.logic10"

    public init() {}

    public var mackieControlObservation: MackieControlObservation {
        guard AXIsProcessTrusted() else {
            return .unavailable(.accessibilityNotTrusted)
        }
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            return .unavailable(.logicNotRunning)
        }

        let root = AXUIElementCreateApplication(application.processIdentifier)
        let windows = arrayAttribute(root, kAXWindowsAttribute)
        guard let setupWindow = windows.first(where: isControlSurfaceSetupWindow) else {
            return .unavailable(.setupWindowClosed)
        }
        let tree = snapshot(setupWindow, depth: 0)
        guard let assignments = ControlSurfaceSetupParser.assignments(in: tree) else {
            return .unavailable(.unreadableSetupWindow)
        }
        return .observed(MackieControlConfigurationClassifier.classify(assignments))
    }

    private func isControlSurfaceSetupWindow(_ element: AXUIElement) -> Bool {
        guard let title = stringAttribute(element, kAXTitleAttribute) else { return false }
        return title.localizedCaseInsensitiveContains("Control Surface")
            && title.localizedCaseInsensitiveContains("Setup")
    }

    private func snapshot(_ element: AXUIElement, depth: Int) -> ControlSurfaceUIElement {
        guard depth <= 12 else { return ControlSurfaceUIElement(strings: []) }
        let names = [
            kAXTitleAttribute,
            kAXValueAttribute,
            kAXDescriptionAttribute,
            kAXHelpAttribute,
        ]
        let strings = names.compactMap { stringAttribute(element, $0) }
        let children = arrayAttribute(element, kAXChildrenAttribute).prefix(2_000).map {
            snapshot($0, depth: depth + 1)
        }
        return ControlSurfaceUIElement(strings: strings, children: children)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private func arrayAttribute(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        attribute(element, name) as? [AXUIElement] ?? []
    }
}
