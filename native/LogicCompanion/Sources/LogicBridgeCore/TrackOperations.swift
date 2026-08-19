import AppKit
import ApplicationServices
import Foundation

public enum LogicTrackScriptingError: Error, Equatable {
    case accessibilityUnavailable
    case logicNotRunning
    case logicNotFocused
    case trackNotFound
    case unsupportedTrackType
    case invalidPosition
    case dialogPresented
    case commandFailed
}

public protocol LogicTrackScripting: Sendable {
    func observeTracks() throws -> [LogicTrackIdentity]
    func create(type: LogicTrackType) throws
    func rename(trackID: String, name: String) throws
    func select(trackID: String) throws
    func duplicate(trackID: String) throws
    func reorder(trackID: String, position: Int) throws
    func delete(trackID: String) throws
    func deletionUndoAvailable() throws -> Bool
}

public protocol TrackOperationsControlling: Sendable {
    func observe(operationID: String) -> TrackOperationResult
    func create(type: LogicTrackType, name: String?, operationID: String, timeoutMilliseconds: Int) -> TrackOperationResult
    func rename(trackID: String, name: String, operationID: String, timeoutMilliseconds: Int) -> TrackOperationResult
    func select(trackID: String, operationID: String, timeoutMilliseconds: Int) -> TrackOperationResult
    func duplicate(trackID: String, name: String?, operationID: String, timeoutMilliseconds: Int) -> TrackOperationResult
    func reorder(trackID: String, position: Int, operationID: String, timeoutMilliseconds: Int) -> TrackOperationResult
    func delete(trackID: String, confirmed: Bool, operationID: String, timeoutMilliseconds: Int) -> TrackOperationResult
}

public final class TrackOperationsController: TrackOperationsControlling, @unchecked Sendable {
    private let scripting: any LogicTrackScripting
    private let policyContextReady: @Sendable () -> Bool
    private let testModeReady: @Sendable () -> Bool
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) -> Void

    public init(
        scripting: any LogicTrackScripting = MacLogicTrackScripting(),
        policyContextReady: @escaping @Sendable () -> Bool,
        testModeReady: @escaping @Sendable () -> Bool,
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
    ) {
        self.scripting = scripting
        self.policyContextReady = policyContextReady
        self.testModeReady = testModeReady
        self.now = now
        self.sleep = sleep
    }

    public func observe(operationID: String) -> TrackOperationResult {
        let startedAt = now()
        guard policyContextReady() else {
            return failure(operationID: operationID, action: .observe, startedAt: startedAt, failure: .projectPolicyMissing)
        }
        do {
            return success(operationID: operationID, action: .observe, startedAt: startedAt, tracks: try scripting.observeTracks())
        } catch {
            return failure(operationID: operationID, action: .observe, startedAt: startedAt, failure: map(error))
        }
    }

    public func create(
        type: LogicTrackType,
        name: String?,
        operationID: String,
        timeoutMilliseconds: Int
    ) -> TrackOperationResult {
        mutate(operationID: operationID, action: .create, timeoutMilliseconds: timeoutMilliseconds) { before in
            guard type != .unknown else { throw LogicTrackScriptingError.unsupportedTrackType }
            if let name { try Self.validate(name: name) }
            try scripting.create(type: type)
            guard var after = waitFor(timeoutMilliseconds: timeoutMilliseconds, condition: {
                let tracks = try? scripting.observeTracks()
                return tracks?.count == before.count + 1 ? tracks : nil
            }), let created = after.first(where: { track in !before.contains(where: { $0.id == track.id }) }) else {
                return nil
            }
            if let name {
                try scripting.rename(trackID: created.id, name: name)
                guard let renamed = waitFor(timeoutMilliseconds: timeoutMilliseconds, condition: {
                    let tracks = try? scripting.observeTracks()
                    return tracks?.first(where: { $0.id == created.id })?.name == name ? tracks : nil
                }) else { return nil }
                after = renamed
            }
            guard after.contains(where: { $0.id == created.id && $0.selected && $0.type == type }) else { return nil }
            return MutationPostcondition(tracks: after, targetTrackID: created.id)
        }
    }

    public func rename(
        trackID: String,
        name: String,
        operationID: String,
        timeoutMilliseconds: Int
    ) -> TrackOperationResult {
        mutate(operationID: operationID, action: .rename, timeoutMilliseconds: timeoutMilliseconds) { before in
            try Self.validate(name: name)
            guard before.contains(where: { $0.id == trackID }) else { throw LogicTrackScriptingError.trackNotFound }
            try scripting.rename(trackID: trackID, name: name)
            guard let after = waitFor(timeoutMilliseconds: timeoutMilliseconds, condition: {
                let tracks = try? scripting.observeTracks()
                return tracks?.first(where: { $0.id == trackID })?.name == name ? tracks : nil
            }) else { return nil }
            return MutationPostcondition(tracks: after, targetTrackID: trackID)
        }
    }

    public func select(
        trackID: String,
        operationID: String,
        timeoutMilliseconds: Int
    ) -> TrackOperationResult {
        mutate(operationID: operationID, action: .select, timeoutMilliseconds: timeoutMilliseconds) { before in
            guard before.contains(where: { $0.id == trackID }) else { throw LogicTrackScriptingError.trackNotFound }
            try scripting.select(trackID: trackID)
            guard let after = waitFor(timeoutMilliseconds: timeoutMilliseconds, condition: {
                let tracks = try? scripting.observeTracks()
                return tracks?.first(where: { $0.id == trackID })?.selected == true ? tracks : nil
            }) else { return nil }
            return MutationPostcondition(tracks: after, targetTrackID: trackID)
        }
    }

    public func duplicate(
        trackID: String,
        name: String?,
        operationID: String,
        timeoutMilliseconds: Int
    ) -> TrackOperationResult {
        mutate(operationID: operationID, action: .duplicate, timeoutMilliseconds: timeoutMilliseconds) { before in
            if let name { try Self.validate(name: name) }
            guard let source = before.first(where: { $0.id == trackID }) else { throw LogicTrackScriptingError.trackNotFound }
            try scripting.duplicate(trackID: trackID)
            guard var after = waitFor(timeoutMilliseconds: timeoutMilliseconds, condition: {
                let tracks = try? scripting.observeTracks()
                return tracks?.count == before.count + 1 ? tracks : nil
            }), let created = after.first(where: { track in !before.contains(where: { $0.id == track.id }) }) else {
                return nil
            }
            if let name {
                try scripting.rename(trackID: created.id, name: name)
                guard let renamed = waitFor(timeoutMilliseconds: timeoutMilliseconds, condition: {
                    let tracks = try? scripting.observeTracks()
                    return tracks?.first(where: { $0.id == created.id })?.name == name ? tracks : nil
                }) else { return nil }
                after = renamed
            }
            guard after.contains(where: {
                $0.id == created.id && $0.selected && ($0.type == source.type || source.type == .unknown)
            }), after.contains(where: { $0.id == source.id }) else { return nil }
            return MutationPostcondition(tracks: after, targetTrackID: created.id)
        }
    }

    public func reorder(
        trackID: String,
        position: Int,
        operationID: String,
        timeoutMilliseconds: Int
    ) -> TrackOperationResult {
        mutate(operationID: operationID, action: .reorder, timeoutMilliseconds: timeoutMilliseconds) { before in
            guard before.indices.contains(position - 1) else { throw LogicTrackScriptingError.invalidPosition }
            guard before.contains(where: { $0.id == trackID }) else { throw LogicTrackScriptingError.trackNotFound }
            try scripting.reorder(trackID: trackID, position: position)
            guard let after = waitFor(timeoutMilliseconds: timeoutMilliseconds, condition: {
                let tracks = try? scripting.observeTracks()
                return tracks?.first(where: { $0.id == trackID })?.position == position ? tracks : nil
            }) else { return nil }
            return MutationPostcondition(tracks: after, targetTrackID: trackID)
        }
    }

    public func delete(
        trackID: String,
        confirmed: Bool,
        operationID: String,
        timeoutMilliseconds: Int
    ) -> TrackOperationResult {
        let startedAt = now()
        guard confirmed else {
            return failure(operationID: operationID, action: .delete, startedAt: startedAt, failure: .confirmationRequired)
        }
        return mutate(operationID: operationID, action: .delete, startedAt: startedAt, timeoutMilliseconds: timeoutMilliseconds) { before in
            guard before.contains(where: { $0.id == trackID }) else { throw LogicTrackScriptingError.trackNotFound }
            try scripting.delete(trackID: trackID)
            guard let after = waitFor(timeoutMilliseconds: timeoutMilliseconds, condition: {
                let tracks = try? scripting.observeTracks()
                return tracks?.count == before.count - 1 && tracks?.contains(where: { $0.id == trackID }) == false ? tracks : nil
            }) else { return nil }
            guard try scripting.deletionUndoAvailable() else {
                return MutationPostcondition(tracks: after, targetTrackID: trackID, failure: .undoUnavailable)
            }
            return MutationPostcondition(tracks: after, targetTrackID: trackID, undoAvailable: true)
        }
    }

    private struct MutationPostcondition {
        let tracks: [LogicTrackIdentity]
        let targetTrackID: String?
        let undoAvailable: Bool
        let failure: TrackOperationFailure?

        init(
            tracks: [LogicTrackIdentity],
            targetTrackID: String?,
            undoAvailable: Bool = false,
            failure: TrackOperationFailure? = nil
        ) {
            self.tracks = tracks
            self.targetTrackID = targetTrackID
            self.undoAvailable = undoAvailable
            self.failure = failure
        }
    }

    private func mutate(
        operationID: String,
        action: TrackOperationAction,
        startedAt: Date? = nil,
        timeoutMilliseconds: Int,
        mutation: ([LogicTrackIdentity]) throws -> MutationPostcondition?
    ) -> TrackOperationResult {
        let startedAt = startedAt ?? now()
        guard policyContextReady() else {
            return failure(operationID: operationID, action: action, startedAt: startedAt, failure: .projectPolicyMissing)
        }
        guard testModeReady() else {
            return failure(operationID: operationID, action: action, startedAt: startedAt, failure: .testModeInactive)
        }
        do {
            let before = try scripting.observeTracks()
            guard let postcondition = try mutation(before) else {
                return failure(
                    operationID: operationID,
                    action: action,
                    startedAt: startedAt,
                    failure: .postconditionFailed,
                    commandDispatched: true,
                    tracks: (try? scripting.observeTracks()) ?? before
                )
            }
            if let postconditionFailure = postcondition.failure {
                return result(
                    operationID: operationID,
                    action: action,
                    startedAt: startedAt,
                    status: .partial,
                    commandDispatched: true,
                    targetTrackID: postcondition.targetTrackID,
                    tracks: postcondition.tracks,
                    failure: postconditionFailure
                )
            }
            return success(
                operationID: operationID,
                action: action,
                startedAt: startedAt,
                commandDispatched: true,
                targetTrackID: postcondition.targetTrackID,
                undoAvailable: postcondition.undoAvailable,
                tracks: postcondition.tracks
            )
        } catch {
            return failure(
                operationID: operationID,
                action: action,
                startedAt: startedAt,
                failure: map(error),
                tracks: (try? scripting.observeTracks()) ?? []
            )
        }
    }

    private func waitFor<Value>(timeoutMilliseconds: Int, condition: () -> Value?) -> Value? {
        let deadline = Date().addingTimeInterval(Double(max(0, timeoutMilliseconds)) / 1_000)
        repeat {
            if let value = condition() { return value }
            sleep(0.05)
        } while Date() < deadline
        return condition()
    }

    private static func validate(name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == name, !trimmed.isEmpty, trimmed.count <= 128,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw TrackOperationFailure.invalidName
        }
    }

    private func map(_ error: Error) -> TrackOperationFailure {
        if let failure = error as? TrackOperationFailure { return failure }
        switch error as? LogicTrackScriptingError {
        case .accessibilityUnavailable: return .accessibilityUnavailable
        case .logicNotRunning: return .logicNotRunning
        case .logicNotFocused: return .logicNotFocused
        case .trackNotFound: return .trackNotFound
        case .unsupportedTrackType: return .unsupportedTrackType
        case .invalidPosition: return .invalidPosition
        case .dialogPresented: return .dialogPresented
        default: return .commandFailed
        }
    }

    private func success(
        operationID: String,
        action: TrackOperationAction,
        startedAt: Date,
        commandDispatched: Bool = false,
        targetTrackID: String? = nil,
        undoAvailable: Bool = false,
        tracks: [LogicTrackIdentity]
    ) -> TrackOperationResult {
        result(
            operationID: operationID,
            action: action,
            startedAt: startedAt,
            status: .succeeded,
            commandDispatched: commandDispatched,
            targetTrackID: targetTrackID,
            undoAvailable: undoAvailable,
            tracks: tracks
        )
    }

    private func failure(
        operationID: String,
        action: TrackOperationAction,
        startedAt: Date,
        failure: TrackOperationFailure,
        commandDispatched: Bool = false,
        tracks: [LogicTrackIdentity] = []
    ) -> TrackOperationResult {
        result(
            operationID: operationID,
            action: action,
            startedAt: startedAt,
            status: .failed,
            commandDispatched: commandDispatched,
            tracks: tracks,
            failure: failure
        )
    }

    private func result(
        operationID: String,
        action: TrackOperationAction,
        startedAt: Date,
        status: OperationStatus,
        commandDispatched: Bool,
        targetTrackID: String? = nil,
        undoAvailable: Bool = false,
        tracks: [LogicTrackIdentity],
        failure: TrackOperationFailure? = nil
    ) -> TrackOperationResult {
        let observedAt = tracks.map(\.observedAt).max() ?? now()
        return TrackOperationResult(
            protocolVersion: bridgeProtocolVersion,
            operationID: operationID,
            status: status,
            reliability: .verifiedUIDriven,
            startedAt: startedAt,
            finishedAt: now(),
            data: TrackOperationData(
                action: action,
                commandDispatched: commandDispatched,
                policyContext: policyContextReady(),
                targetTrackID: targetTrackID,
                undoAvailable: undoAvailable,
                tracks: tracks,
                failure: failure
            ),
            evidence: [Evidence(
                source: "Logic track header and inspector accessibility observation",
                observedAt: observedAt,
                value: .object([
                    "trackCount": .number(Double(tracks.count)),
                    "selectedTrackIds": .array(tracks.filter(\.selected).map { .string($0.id) }),
                    "action": .string(action.rawValue),
                ])
            )]
        )
    }
}

public final class MacLogicTrackScripting: LogicTrackScripting, @unchecked Sendable {
    private struct Record {
        var id: String
        var element: AXUIElement
        var name: String
        var position: Int
        var type: LogicTrackType
    }

    private struct Header {
        let element: AXUIElement
        let position: Int
        let name: String
        let selected: Bool
    }

    private let lock = NSLock()
    private var records: [Record] = []

    public init() {}

    public func observeTracks() throws -> [LogicTrackIdentity] {
        try lock.withLock {
            let application = try logicApplication(requireFocus: false)
            try rejectModal(application)
            let headers = descendants(of: application, maximum: 12_000).compactMap(parseHeader).sorted { $0.position < $1.position }
            let selectedType = classifySelectedTrack(in: application)
            var unmatchedRecords = records
            var nextRecords: [Record] = []
            let observedAt = Date()
            let tracks = headers.map { header -> LogicTrackIdentity in
                let fallbackMatches = unmatchedRecords.indices.filter {
                    unmatchedRecords[$0].name == header.name && unmatchedRecords[$0].position == header.position
                }
                let matchingIndex = unmatchedRecords.firstIndex(where: { CFEqual($0.element, header.element) })
                    ?? (fallbackMatches.count == 1 ? fallbackMatches[0] : nil)
                var record: Record
                if let matchingIndex {
                    record = unmatchedRecords.remove(at: matchingIndex)
                    record.element = header.element
                    record.name = header.name
                    record.position = header.position
                } else {
                    record = Record(
                        id: "track-\(UUID().uuidString.lowercased())",
                        element: header.element,
                        name: header.name,
                        position: header.position,
                        type: .unknown
                    )
                }
                if header.selected, let selectedType { record.type = selectedType }
                nextRecords.append(record)
                return LogicTrackIdentity(
                    id: record.id,
                    position: header.position,
                    type: record.type,
                    name: header.name,
                    selected: header.selected,
                    observedAt: observedAt
                )
            }
            records = nextRecords
            return tracks
        }
    }

    public func create(type: LogicTrackType) throws {
        let title = switch type {
        case .softwareInstrument: "New Software Instrument Track"
        case .audio: "New Audio Track"
        case .externalMIDI: "New External MIDI Track"
        case .unknown: throw LogicTrackScriptingError.unsupportedTrackType
        }
        try performMenuItem(menu: "Track", title: title)
    }

    public func rename(trackID: String, name: String) throws {
        try lock.withLock {
            let record = try record(trackID)
            guard let field = descendants(of: record.element, maximum: 100).first(where: {
                attributeString($0, kAXRoleAttribute) == kAXTextFieldRole &&
                    (attributeString($0, kAXHelpAttribute)?.contains("Name field") == true)
            }) else { throw LogicTrackScriptingError.commandFailed }
            guard AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, name as CFTypeRef) == .success else {
                throw LogicTrackScriptingError.commandFailed
            }
            bind(trackID: trackID, toSelectedIn: try logicApplication(requireFocus: false), name: name)
        }
    }

    public func select(trackID: String) throws {
        try lock.withLock {
            let record = try record(trackID)
            guard let focus = descendants(of: record.element, maximum: 100).first(where: {
                attributeString($0, kAXRoleAttribute) == kAXRadioButtonRole &&
                    attributeString($0, kAXDescriptionAttribute) == "Has Focus"
            }), AXUIElementPerformAction(focus, kAXPressAction as CFString) == .success else {
                throw LogicTrackScriptingError.commandFailed
            }
        }
    }

    public func duplicate(trackID: String) throws {
        try select(trackID: trackID)
        try performMenuItem(menu: "Track", title: "New Track With Duplicate Settings")
    }

    public func reorder(trackID: String, position: Int) throws {
        try lock.withLock {
            let application = try logicApplication(requireFocus: true)
            try rejectModal(application)
            let record = try record(trackID)
            let ordered = records.sorted { $0.position < $1.position }
            guard ordered.indices.contains(position - 1) else { throw LogicTrackScriptingError.invalidPosition }
            let target = ordered[position - 1]
            guard record.position != position else { return }
            guard let sourceFrame = frame(record.element), let targetFrame = frame(target.element) else {
                throw LogicTrackScriptingError.commandFailed
            }
            let x = sourceFrame.maxX - min(12, sourceFrame.width / 4)
            let sourcePoint = CGPoint(x: x, y: sourceFrame.midY)
            let targetY = record.position < position ? targetFrame.maxY - 2 : targetFrame.minY + 2
            let targetPoint = CGPoint(x: x, y: targetY)
            guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: sourcePoint, mouseButton: .left),
                  let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: targetPoint, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: targetPoint, mouseButton: .left) else {
                throw LogicTrackScriptingError.commandFailed
            }
            down.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.08)
            drag.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.08)
            up.post(tap: .cghidEventTap)
        }
    }

    public func delete(trackID: String) throws {
        try select(trackID: trackID)
        try performMenuItem(menu: "Track", title: "Delete Track")
    }

    public func deletionUndoAvailable() throws -> Bool {
        let application = try logicApplication(requireFocus: false)
        guard let item = try openMenu(application: application, title: "Edit").first(where: {
            attributeString($0, kAXRoleAttribute) == kAXMenuItemRole &&
                (attributeString($0, kAXTitleAttribute)?.hasPrefix("Undo Delete Track") == true)
        }) else { return false }
        let enabled = attributeBool(item, kAXEnabledAttribute) == true
        if let menuBarItem = menuBarItem(application: application, title: "Edit") {
            _ = AXUIElementPerformAction(menuBarItem, kAXPressAction as CFString)
        }
        return enabled
    }

    private func performMenuItem(menu: String, title: String) throws {
        let application = try logicApplication(requireFocus: false)
        try rejectModal(application)
        let elements = try openMenu(application: application, title: menu)
        guard let item = elements.first(where: {
            attributeString($0, kAXRoleAttribute) == kAXMenuItemRole &&
                attributeString($0, kAXTitleAttribute) == title &&
                attributeBool($0, kAXEnabledAttribute) != false
        }), AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
            throw LogicTrackScriptingError.commandFailed
        }
    }

    private func openMenu(application: AXUIElement, title: String) throws -> [AXUIElement] {
        guard let item = menuBarItem(application: application, title: title),
              AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
            throw LogicTrackScriptingError.commandFailed
        }
        return descendants(of: item, maximum: 500)
    }

    private func menuBarItem(application: AXUIElement, title: String) -> AXUIElement? {
        descendants(of: application, maximum: 500).first {
            attributeString($0, kAXRoleAttribute) == kAXMenuBarItemRole &&
                attributeString($0, kAXTitleAttribute) == title
        }
    }

    private func logicApplication(requireFocus: Bool) throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw LogicTrackScriptingError.accessibilityUnavailable }
        guard let logic = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.logic10" }) else {
            throw LogicTrackScriptingError.logicNotRunning
        }
        if requireFocus, NSWorkspace.shared.frontmostApplication?.processIdentifier != logic.processIdentifier {
            throw LogicTrackScriptingError.logicNotFocused
        }
        return AXUIElementCreateApplication(logic.processIdentifier)
    }

    private func rejectModal(_ application: AXUIElement) throws {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value else { return }
        if attributeBool(value as! AXUIElement, kAXModalAttribute) == true {
            throw LogicTrackScriptingError.dialogPresented
        }
    }

    private func record(_ id: String) throws -> Record {
        guard let record = records.first(where: { $0.id == id }) else { throw LogicTrackScriptingError.trackNotFound }
        return record
    }

    private func bind(trackID: String, toSelectedIn application: AXUIElement, name: String) {
        guard let header = descendants(of: application, maximum: 12_000).compactMap(parseHeader).first(where: { $0.selected }) else { return }
        if let index = records.firstIndex(where: { $0.id == trackID }) {
            records[index].element = header.element
            records[index].name = name
            records[index].position = header.position
        }
    }

    private func parseHeader(_ element: AXUIElement) -> Header? {
        guard attributeString(element, kAXRoleAttribute) == kAXGroupRole,
              let description = attributeString(element, kAXDescriptionAttribute),
              let match = description.wholeMatch(of: /Track ([0-9]+) “(.+)”(?:,.*)?/) else { return nil }
        let selected = attributeBool(element, kAXSelectedAttribute) == true || descendants(of: element, maximum: 100).contains {
            attributeString($0, kAXRoleAttribute) == kAXRadioButtonRole &&
                attributeString($0, kAXDescriptionAttribute) == "Has Focus" && attributeInt($0, kAXValueAttribute) == 1
        }
        return Header(
            element: element,
            position: Int(match.1) ?? 0,
            name: String(match.2),
            selected: selected
        )
    }

    private func classifySelectedTrack(in application: AXUIElement) -> LogicTrackType? {
        let elements = descendants(of: application, maximum: 12_000)
        let descriptions = elements.compactMap { attributeString($0, kAXDescriptionAttribute) }
        let values = elements.compactMap { attributeString($0, kAXValueAttribute) }
        if values.contains("Audio Defaults Region:") || descriptions.contains("Audio Defaults Region:") { return .audio }
        guard values.contains("MIDI Defaults Region:") || descriptions.contains("MIDI Defaults Region:") else { return nil }
        return descriptions.contains("midi assign knob") ? .externalMIDI : .softwareInstrument
    }

    private func descendants(of root: AXUIElement, maximum: Int) -> [AXUIElement] {
        var output: [AXUIElement] = []
        var queue = [root]
        while let element = queue.first, output.count < maximum {
            queue.removeFirst()
            output.append(element)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
               let children = value as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return output
    }

    private func attributeString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func attributeBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private func attributeInt(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}
