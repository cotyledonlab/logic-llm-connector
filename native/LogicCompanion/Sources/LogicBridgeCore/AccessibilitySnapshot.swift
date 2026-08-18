import AppKit
import ApplicationServices
import Foundation

public struct AXSnapshotLimits: Codable, Sendable, Equatable {
    public let maxDepth: Int
    public let maxNodes: Int

    public init(maxDepth: Int, maxNodes: Int) {
        self.maxDepth = maxDepth
        self.maxNodes = maxNodes
    }
}

public struct AXApplicationSnapshot: Codable, Sendable, Equatable {
    public let bundleIdentifier: String
    public let pid: Int32
}

public struct AXNodeSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let parentID: String?
    public let role: String
    public let subrole: String?
    public let identifier: String?
    public let enabled: Bool?
    public let focused: Bool?
    public let childCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case parentID = "parentId"
        case role
        case subrole
        case identifier
        case enabled
        case focused
        case childCount
    }
}

public struct AXSnapshotData: Codable, Sendable, Equatable {
    public let application: AXApplicationSnapshot
    public let capturedAt: Date
    public let limits: AXSnapshotLimits
    public let truncated: Bool
    public let nodes: [AXNodeSnapshot]
}

public enum AXSnapshotError: Error, Equatable {
    case accessibilityNotTrusted
    case logicNotRunning
    case invalidLimits
}

public struct MacLogicAXSnapshotter {
    private let bundleIdentifier = "com.apple.logic10"

    public init() {}

    public func capture(limits: AXSnapshotLimits) throws -> AXSnapshotData {
        guard (0...8).contains(limits.maxDepth), (1...1000).contains(limits.maxNodes) else {
            throw AXSnapshotError.invalidLimits
        }
        guard AXIsProcessTrusted() else {
            throw AXSnapshotError.accessibilityNotTrusted
        }
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            throw AXSnapshotError.logicNotRunning
        }

        let root = AXUIElementCreateApplication(application.processIdentifier)
        var pending: [(element: AXUIElement, parentID: String?, depth: Int)] = [
            (root, nil, 0)
        ]
        var cursor = 0
        var nodes: [AXNodeSnapshot] = []
        var truncated = false

        while cursor < pending.count, nodes.count < limits.maxNodes {
            let entry = pending[cursor]
            cursor += 1
            let nodeID = "node-\(nodes.count)"
            let children = arrayAttribute(entry.element, kAXChildrenAttribute)
            nodes.append(
                AXNodeSnapshot(
                    id: nodeID,
                    parentID: entry.parentID,
                    role: stringAttribute(entry.element, kAXRoleAttribute) ?? "AXUnknown",
                    subrole: stringAttribute(entry.element, kAXSubroleAttribute),
                    identifier: stringAttribute(entry.element, kAXIdentifierAttribute),
                    enabled: boolAttribute(entry.element, kAXEnabledAttribute),
                    focused: boolAttribute(entry.element, kAXFocusedAttribute),
                    childCount: children.count
                )
            )

            if entry.depth < limits.maxDepth {
                pending.append(contentsOf: children.map {
                    (element: $0, parentID: Optional(nodeID), depth: entry.depth + 1)
                })
            } else if !children.isEmpty {
                truncated = true
            }
        }
        if cursor < pending.count { truncated = true }

        return AXSnapshotData(
            application: AXApplicationSnapshot(
                bundleIdentifier: bundleIdentifier,
                pid: application.processIdentifier
            ),
            capturedAt: Date(),
            limits: limits,
            truncated: truncated,
            nodes: nodes
        )
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

    private func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
        (attribute(element, name) as? NSNumber)?.boolValue
    }

    private func arrayAttribute(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        attribute(element, name) as? [AXUIElement] ?? []
    }
}
