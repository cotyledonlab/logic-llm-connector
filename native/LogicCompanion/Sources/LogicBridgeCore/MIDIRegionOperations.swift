import Foundation

public enum LogicMIDIRegionScriptingError: Error, Equatable {
    case accessibilityUnavailable
    case logicNotRunning
    case logicNotFocused
    case trackNotFound
    case regionNotFound
    case noteNotFound
    case dialogPresented
    case commandFailed
}

public protocol LogicMIDIRegionScripting: Sendable {
    func observeRegions() throws -> [MIDIRegionIdentity]
    func create(trackID: String, name: String, position: MusicalTime, length: MusicalTime, notes: [MIDINoteContent]) throws
    func rename(regionID: String, name: String) throws
    func move(regionID: String, position: MusicalTime) throws
    func resize(regionID: String, length: MusicalTime) throws
    func duplicate(regionID: String, position: MusicalTime) throws
    func split(regionID: String, position: MusicalTime) throws
    func updateNote(regionID: String, noteID: String, note: MIDINoteContent) throws
    func replaceNotes(regionID: String, notes: [MIDINoteContent]) throws
    func delete(regionID: String) throws
    func deletionUndoAvailable() throws -> Bool
    func verifyPlayback(regionID: String, timeoutMilliseconds: Int) throws -> Bool
}

public protocol MIDIRegionOperationsControlling: Sendable {
    func observe(operationID: String) -> MIDIRegionOperationResult
    func create(trackID: String, name: String, position: MusicalTime, length: MusicalTime, notes: [MIDINoteContent], operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult
    func rename(regionID: String, name: String, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult
    func move(regionID: String, position: MusicalTime, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult
    func resize(regionID: String, length: MusicalTime, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult
    func duplicate(regionID: String, position: MusicalTime, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult
    func split(regionID: String, position: MusicalTime, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult
    func updateNote(regionID: String, noteID: String, note: MIDINoteContent, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult
    func replaceNotes(regionID: String, notes: [MIDINoteContent], operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult
    func delete(regionID: String, confirmed: Bool, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult
    func verifyPlayback(regionID: String, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult
}

public final class MIDIRegionOperationsController: MIDIRegionOperationsControlling, @unchecked Sendable {
    private let scripting: any LogicMIDIRegionScripting
    private let policyContextReady: @Sendable () -> Bool
    private let testModeReady: @Sendable () -> Bool
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) -> Void

    public init(
        scripting: any LogicMIDIRegionScripting,
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

    public func observe(operationID: String) -> MIDIRegionOperationResult {
        let startedAt = now()
        guard policyContextReady() else { return failure(operationID, .observe, startedAt, .projectPolicyMissing) }
        do { return result(operationID, .observe, startedAt, .succeeded, false, regions: try scripting.observeRegions()) }
        catch { return failure(operationID, .observe, startedAt, map(error)) }
    }

    public func create(
        trackID: String,
        name: String,
        position: MusicalTime,
        length: MusicalTime,
        notes: [MIDINoteContent],
        operationID: String,
        timeoutMilliseconds: Int
    ) -> MIDIRegionOperationResult {
        mutate(operationID, .create, timeoutMilliseconds) { before in
            try Self.validate(name: name)
            try Self.validate(position: position, duration: false)
            try Self.validate(position: length, duration: true)
            try notes.forEach { try Self.validate(note: $0, regionLength: length) }
            try scripting.create(trackID: trackID, name: name, position: position, length: length, notes: notes)
            guard let after = waitFor(timeoutMilliseconds, { () -> [MIDIRegionIdentity]? in
                let value = try? scripting.observeRegions()
                return value?.count == before.count + 1 ? value : nil
            }), let created = after.first(where: { candidate in !before.contains(where: { $0.id == candidate.id }) }) else { return nil }
            var differences = Self.differences(requested: notes, observed: created.notes)
            differences += Self.difference(targetID: created.id, field: "name", requested: .string(name), observed: .string(created.name), equal: created.name == name)
            differences += Self.difference(targetID: created.id, field: "position", requested: Self.json(position), observed: Self.json(created.position), equal: created.position == position)
            differences += Self.difference(targetID: created.id, field: "length", requested: Self.json(length), observed: Self.json(created.length), equal: created.length == length)
            return Postcondition(regions: after, targetRegionID: created.id, createdRegionIDs: [created.id], differences: differences)
        }
    }

    public func rename(regionID: String, name: String, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult {
        mutate(operationID, .rename, timeoutMilliseconds) { before in
            try Self.validate(name: name)
            try Self.requireRegion(regionID, in: before)
            try scripting.rename(regionID: regionID, name: name)
            guard let after = waitFor(timeoutMilliseconds, { self.observed(where: { self.region(regionID, in: $0)?.name == name }) }) else { return nil }
            return Postcondition(regions: after, targetRegionID: regionID)
        }
    }

    public func move(regionID: String, position: MusicalTime, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult {
        mutate(operationID, .move, timeoutMilliseconds) { before in
            try Self.validate(position: position, duration: false)
            try Self.requireRegion(regionID, in: before)
            try scripting.move(regionID: regionID, position: position)
            guard let after = waitFor(timeoutMilliseconds, { self.observed(where: { self.region(regionID, in: $0)?.position == position }) }) else { return nil }
            return Postcondition(regions: after, targetRegionID: regionID)
        }
    }

    public func resize(regionID: String, length: MusicalTime, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult {
        mutate(operationID, .resize, timeoutMilliseconds) { before in
            try Self.validate(position: length, duration: true)
            try Self.requireRegion(regionID, in: before)
            try scripting.resize(regionID: regionID, length: length)
            guard let after = waitFor(timeoutMilliseconds, { self.observed(where: { self.region(regionID, in: $0)?.length == length }) }) else { return nil }
            return Postcondition(regions: after, targetRegionID: regionID)
        }
    }

    public func duplicate(regionID: String, position: MusicalTime, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult {
        mutate(operationID, .duplicate, timeoutMilliseconds) { before in
            try Self.validate(position: position, duration: false)
            let source = try Self.requireRegion(regionID, in: before)
            try scripting.duplicate(regionID: regionID, position: position)
            guard let after = waitFor(timeoutMilliseconds, { () -> [MIDIRegionIdentity]? in
                let value = try? self.scripting.observeRegions()
                return value?.count == before.count + 1 ? value : nil
            }), let created = after.first(where: { candidate in !before.contains(where: { $0.id == candidate.id }) }) else { return nil }
            var differences = Self.differences(requested: source.notes.map(\.content), observed: created.notes)
            differences += Self.difference(targetID: created.id, field: "position", requested: Self.json(position), observed: Self.json(created.position), equal: created.position == position)
            differences += Self.difference(targetID: created.id, field: "length", requested: Self.json(source.length), observed: Self.json(created.length), equal: created.length == source.length)
            return Postcondition(regions: after, targetRegionID: created.id, createdRegionIDs: [created.id], differences: differences)
        }
    }

    public func split(regionID: String, position: MusicalTime, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult {
        mutate(operationID, .split, timeoutMilliseconds) { before in
            let source = try Self.requireRegion(regionID, in: before)
            try Self.validate(position: position, duration: false)
            let end = source.position.ticks + source.length.ticks
            guard position.ppq == source.position.ppq, position.ticks > source.position.ticks, position.ticks < end else {
                throw MIDIRegionOperationFailure.invalidSplitPosition
            }
            try scripting.split(regionID: regionID, position: position)
            guard let after = waitFor(timeoutMilliseconds, { () -> [MIDIRegionIdentity]? in
                let value = try? self.scripting.observeRegions()
                return value?.count == before.count + 1 ? value : nil
            }) else { return nil }
            let affected = after.filter { $0.trackID == source.trackID && $0.position.ticks >= source.position.ticks && $0.position.ticks < end }
            guard affected.count >= 2 else { return nil }
            let created = affected.map(\.id).filter { id in !before.contains(where: { $0.id == id }) }
            return Postcondition(regions: after, targetRegionID: regionID, createdRegionIDs: created)
        }
    }

    public func updateNote(regionID: String, noteID: String, note: MIDINoteContent, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult {
        mutate(operationID, .updateNote, timeoutMilliseconds) { before in
            let source = try Self.requireRegion(regionID, in: before)
            guard source.notes.contains(where: { $0.id == noteID }) else { throw LogicMIDIRegionScriptingError.noteNotFound }
            try Self.validate(note: note, regionLength: source.length)
            try scripting.updateNote(regionID: regionID, noteID: noteID, note: note)
            guard let after = waitFor(timeoutMilliseconds, { self.observed(where: { self.region(regionID, in: $0)?.notes.first(where: { $0.id == noteID })?.content == note }) }) else { return nil }
            return Postcondition(regions: after, targetRegionID: regionID)
        }
    }

    public func replaceNotes(regionID: String, notes: [MIDINoteContent], operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult {
        mutate(operationID, .replaceNotes, timeoutMilliseconds) { before in
            let source = try Self.requireRegion(regionID, in: before)
            try notes.forEach { try Self.validate(note: $0, regionLength: source.length) }
            try scripting.replaceNotes(regionID: regionID, notes: notes)
            guard let after = waitFor(timeoutMilliseconds, { () -> [MIDIRegionIdentity]? in
                guard let value = try? self.scripting.observeRegions(), let region = self.region(regionID, in: value) else { return nil }
                return region.notes.count == notes.count ? value : nil
            }), let updated = region(regionID, in: after) else { return nil }
            return Postcondition(regions: after, targetRegionID: regionID, differences: Self.differences(requested: notes, observed: updated.notes))
        }
    }

    public func delete(regionID: String, confirmed: Bool, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult {
        let startedAt = now()
        guard confirmed else { return failure(operationID, .delete, startedAt, .confirmationRequired) }
        return mutate(operationID, .delete, timeoutMilliseconds, startedAt: startedAt) { before in
            try Self.requireRegion(regionID, in: before)
            try scripting.delete(regionID: regionID)
            guard let after = waitFor(timeoutMilliseconds, { self.observed(where: { self.region(regionID, in: $0) == nil }) }) else { return nil }
            guard try scripting.deletionUndoAvailable() else {
                return Postcondition(regions: after, targetRegionID: regionID, failure: .undoUnavailable)
            }
            return Postcondition(regions: after, targetRegionID: regionID, undoAvailable: true)
        }
    }

    public func verifyPlayback(regionID: String, operationID: String, timeoutMilliseconds: Int) -> MIDIRegionOperationResult {
        let startedAt = now()
        guard policyContextReady() else { return failure(operationID, .verifyPlayback, startedAt, .projectPolicyMissing) }
        guard testModeReady() else { return failure(operationID, .verifyPlayback, startedAt, .testModeInactive) }
        do {
            let regions = try scripting.observeRegions()
            let target = try Self.requireRegion(regionID, in: regions)
            guard target.active, try scripting.verifyPlayback(regionID: regionID, timeoutMilliseconds: timeoutMilliseconds) else {
                return failure(operationID, .verifyPlayback, startedAt, .playbackNotObserved, true, regions)
            }
            return result(operationID, .verifyPlayback, startedAt, .succeeded, true, targetRegionID: regionID, playbackVerified: true, regions: try scripting.observeRegions())
        } catch { return failure(operationID, .verifyPlayback, startedAt, map(error), true, (try? scripting.observeRegions()) ?? []) }
    }

    private struct Postcondition {
        let regions: [MIDIRegionIdentity]
        let targetRegionID: String?
        var createdRegionIDs: [String] = []
        var differences: [MIDIFidelityDifference] = []
        var undoAvailable = false
        var failure: MIDIRegionOperationFailure?
    }

    private func mutate(
        _ operationID: String,
        _ action: MIDIRegionOperationAction,
        _ timeoutMilliseconds: Int,
        startedAt: Date? = nil,
        mutation: ([MIDIRegionIdentity]) throws -> Postcondition?
    ) -> MIDIRegionOperationResult {
        let startedAt = startedAt ?? now()
        guard policyContextReady() else { return failure(operationID, action, startedAt, .projectPolicyMissing) }
        guard testModeReady() else { return failure(operationID, action, startedAt, .testModeInactive) }
        do {
            let before = try scripting.observeRegions()
            guard let post = try mutation(before) else {
                return failure(operationID, action, startedAt, .postconditionFailed, true, (try? scripting.observeRegions()) ?? before)
            }
            let partialFailure = post.failure ?? (post.differences.isEmpty ? nil : .postconditionFailed)
            return result(
                operationID, action, startedAt, partialFailure == nil ? .succeeded : .partial, true,
                targetRegionID: post.targetRegionID, createdRegionIDs: post.createdRegionIDs,
                differences: post.differences, undoAvailable: post.undoAvailable,
                regions: post.regions, failure: partialFailure
            )
        } catch { return failure(operationID, action, startedAt, map(error), false, (try? scripting.observeRegions()) ?? []) }
    }

    private func waitFor<Value>(_ timeoutMilliseconds: Int, _ condition: () -> Value?) -> Value? {
        let deadline = Date().addingTimeInterval(Double(max(0, timeoutMilliseconds)) / 1_000)
        repeat {
            if let value = condition() { return value }
            sleep(0.05)
        } while Date() < deadline
        return condition()
    }

    private func observed(where predicate: ([MIDIRegionIdentity]) -> Bool) -> [MIDIRegionIdentity]? {
        guard let value = try? scripting.observeRegions() else { return nil }
        return predicate(value) ? value : nil
    }

    private func region(_ id: String, in regions: [MIDIRegionIdentity]) -> MIDIRegionIdentity? {
        regions.first(where: { $0.id == id })
    }

    @discardableResult private static func requireRegion(_ id: String, in regions: [MIDIRegionIdentity]) throws -> MIDIRegionIdentity {
        guard let value = regions.first(where: { $0.id == id }) else { throw LogicMIDIRegionScriptingError.regionNotFound }
        return value
    }

    private static func validate(position: MusicalTime, duration: Bool) throws {
        guard position.ppq == logicMusicalTimePPQ, duration ? position.ticks > 0 : position.ticks >= 0 else {
            throw MIDIRegionOperationFailure.invalidMusicalTime
        }
    }

    private static func validate(note: MIDINoteContent, regionLength: MusicalTime) throws {
        guard note.onset.ppq == logicMusicalTimePPQ, note.duration.ppq == logicMusicalTimePPQ,
              (0 ... 127).contains(note.pitch), (1 ... 127).contains(note.velocity),
              (1 ... 16).contains(note.channel), note.onset.ticks >= 0, note.duration.ticks > 0,
              note.onset.ticks + note.duration.ticks <= regionLength.ticks else {
            throw MIDIRegionOperationFailure.invalidNote
        }
    }

    private static func validate(name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == name, !name.isEmpty, name.count <= 128,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw MIDIRegionOperationFailure.invalidName
        }
    }

    private static func differences(requested: [MIDINoteContent], observed: [MIDINoteIdentity]) -> [MIDIFidelityDifference] {
        let requested = requested.sorted(by: noteOrder)
        let observed = observed.sorted { noteOrder($0.content, $1.content) }
        var output: [MIDIFidelityDifference] = []
        if requested.count != observed.count {
            output.append(.init(field: "notes.count", requested: .number(Double(requested.count)), observed: .number(Double(observed.count)), reason: "Logic returned a different note count"))
        }
        for (index, pair) in zip(requested, observed).enumerated() {
            let (expected, actual) = pair
            let prefix = "notes[\(index)]"
            output += difference(targetID: actual.id, field: "\(prefix).pitch", requested: .number(Double(expected.pitch)), observed: .number(Double(actual.pitch)), equal: expected.pitch == actual.pitch)
            output += difference(targetID: actual.id, field: "\(prefix).onset", requested: json(expected.onset), observed: json(actual.onset), equal: expected.onset == actual.onset)
            output += difference(targetID: actual.id, field: "\(prefix).duration", requested: json(expected.duration), observed: json(actual.duration), equal: expected.duration == actual.duration)
            output += difference(targetID: actual.id, field: "\(prefix).velocity", requested: .number(Double(expected.velocity)), observed: .number(Double(actual.velocity)), equal: expected.velocity == actual.velocity)
            output += difference(targetID: actual.id, field: "\(prefix).channel", requested: .number(Double(expected.channel)), observed: .number(Double(actual.channel)), equal: expected.channel == actual.channel)
        }
        return output
    }

    private static func noteOrder(_ lhs: MIDINoteContent, _ rhs: MIDINoteContent) -> Bool {
        (lhs.onset.ticks, lhs.pitch, lhs.channel, lhs.duration.ticks, lhs.velocity) <
            (rhs.onset.ticks, rhs.pitch, rhs.channel, rhs.duration.ticks, rhs.velocity)
    }

    private static func difference(targetID: String?, field: String, requested: JSONValue, observed: JSONValue, equal: Bool) -> [MIDIFidelityDifference] {
        equal ? [] : [.init(targetID: targetID, field: field, requested: requested, observed: observed, reason: "Logic observed a different value")]
    }

    private static func json(_ value: MusicalTime) -> JSONValue {
        .object(["ticks": .number(Double(value.ticks)), "ppq": .number(Double(value.ppq))])
    }

    private func map(_ error: Error) -> MIDIRegionOperationFailure {
        if let failure = error as? MIDIRegionOperationFailure { return failure }
        switch error as? LogicMIDIRegionScriptingError {
        case .accessibilityUnavailable: return .accessibilityUnavailable
        case .logicNotRunning: return .logicNotRunning
        case .logicNotFocused: return .logicNotFocused
        case .trackNotFound: return .trackNotFound
        case .regionNotFound: return .regionNotFound
        case .noteNotFound: return .noteNotFound
        case .dialogPresented: return .dialogPresented
        default: return .commandFailed
        }
    }

    private func failure(
        _ operationID: String,
        _ action: MIDIRegionOperationAction,
        _ startedAt: Date,
        _ failure: MIDIRegionOperationFailure,
        _ commandDispatched: Bool = false,
        _ regions: [MIDIRegionIdentity] = []
    ) -> MIDIRegionOperationResult {
        result(operationID, action, startedAt, .failed, commandDispatched, regions: regions, failure: failure)
    }

    private func result(
        _ operationID: String,
        _ action: MIDIRegionOperationAction,
        _ startedAt: Date,
        _ status: OperationStatus,
        _ commandDispatched: Bool,
        targetRegionID: String? = nil,
        createdRegionIDs: [String] = [],
        differences: [MIDIFidelityDifference] = [],
        playbackVerified: Bool = false,
        undoAvailable: Bool = false,
        regions: [MIDIRegionIdentity],
        failure: MIDIRegionOperationFailure? = nil
    ) -> MIDIRegionOperationResult {
        let observedAt = regions.map(\.observedAt).max() ?? now()
        return MIDIRegionOperationResult(
            protocolVersion: bridgeProtocolVersion,
            operationID: operationID,
            status: status,
            reliability: .verifiedUIDriven,
            startedAt: startedAt,
            finishedAt: now(),
            data: MIDIRegionOperationData(
                action: action,
                commandDispatched: commandDispatched,
                policyContext: policyContextReady(),
                targetRegionID: targetRegionID,
                createdRegionIDs: createdRegionIDs,
                fidelityDifferences: differences,
                playbackVerified: playbackVerified,
                undoAvailable: undoAvailable,
                regions: regions,
                failure: failure
            ),
            evidence: [Evidence(source: "Logic MIDI region and event observation", observedAt: observedAt, value: .object([
                "action": .string(action.rawValue),
                "regionCount": .number(Double(regions.count)),
                "noteCount": .number(Double(regions.reduce(0) { $0 + $1.notes.count })),
                "exactFidelity": .bool(differences.isEmpty),
            ]))]
        )
    }
}
