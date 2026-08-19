import Foundation
import Testing

@testable import LogicBridgeCore

private final class FakeTrackScripting: LogicTrackScripting, @unchecked Sendable {
    private let lock = NSLock()
    private var tracks: [LogicTrackIdentity]
    var undoAvailable = true
    var commandError: LogicTrackScriptingError?

    init(tracks: [LogicTrackIdentity] = [
        LogicTrackIdentity(
            id: "track-a",
            position: 1,
            type: .softwareInstrument,
            name: "Keys",
            selected: true,
            observedAt: Date(timeIntervalSince1970: 1)
        ),
        LogicTrackIdentity(
            id: "track-b",
            position: 2,
            type: .audio,
            name: "Voice",
            selected: false,
            observedAt: Date(timeIntervalSince1970: 1)
        ),
    ]) {
        self.tracks = tracks
    }

    func observeTracks() throws -> [LogicTrackIdentity] { lock.withLock { tracks } }

    func create(type: LogicTrackType) throws {
        try failIfNeeded()
        lock.withLock {
            tracks = tracks.map { copy($0, selected: false) }
            tracks.append(LogicTrackIdentity(
                id: "track-\(tracks.count + 1)",
                position: tracks.count + 1,
                type: type,
                name: type == .audio ? "Audio 1" : type == .externalMIDI ? "Off 1" : "Instrument 1",
                selected: true,
                observedAt: Date(timeIntervalSince1970: 2)
            ))
        }
    }

    func rename(trackID: String, name: String) throws {
        try failIfNeeded()
        try mutate(trackID) { copy($0, name: name) }
    }

    func select(trackID: String) throws {
        try failIfNeeded()
        try lock.withLock {
            guard tracks.contains(where: { $0.id == trackID }) else { throw LogicTrackScriptingError.trackNotFound }
            tracks = tracks.map { copy($0, selected: $0.id == trackID) }
        }
    }

    func duplicate(trackID: String) throws {
        try failIfNeeded()
        try lock.withLock {
            guard let source = tracks.first(where: { $0.id == trackID }) else { throw LogicTrackScriptingError.trackNotFound }
            tracks = tracks.map { copy($0, selected: false) }
            tracks.append(LogicTrackIdentity(
                id: "track-\(tracks.count + 1)",
                position: tracks.count + 1,
                type: source.type,
                name: source.name,
                selected: true,
                observedAt: Date(timeIntervalSince1970: 2)
            ))
        }
    }

    func reorder(trackID: String, position: Int) throws {
        try failIfNeeded()
        try lock.withLock {
            guard let source = tracks.firstIndex(where: { $0.id == trackID }) else { throw LogicTrackScriptingError.trackNotFound }
            guard tracks.indices.contains(position - 1) else { throw LogicTrackScriptingError.invalidPosition }
            let track = tracks.remove(at: source)
            tracks.insert(track, at: position - 1)
            tracks = tracks.enumerated().map { index, value in copy(value, position: index + 1) }
        }
    }

    func delete(trackID: String) throws {
        try failIfNeeded()
        try lock.withLock {
            guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { throw LogicTrackScriptingError.trackNotFound }
            tracks.remove(at: index)
            tracks = tracks.enumerated().map { offset, value in copy(value, position: offset + 1) }
        }
    }

    func deletionUndoAvailable() throws -> Bool { undoAvailable }

    private func mutate(_ id: String, transform: (LogicTrackIdentity) -> LogicTrackIdentity) throws {
        try lock.withLock {
            guard let index = tracks.firstIndex(where: { $0.id == id }) else { throw LogicTrackScriptingError.trackNotFound }
            tracks[index] = transform(tracks[index])
        }
    }

    private func failIfNeeded() throws {
        if let commandError { throw commandError }
    }

    private func copy(
        _ track: LogicTrackIdentity,
        position: Int? = nil,
        name: String? = nil,
        selected: Bool? = nil
    ) -> LogicTrackIdentity {
        LogicTrackIdentity(
            id: track.id,
            position: position ?? track.position,
            type: track.type,
            name: name ?? track.name,
            selected: selected ?? track.selected,
            observedAt: Date(timeIntervalSince1970: 2)
        )
    }
}

private func controller(
    scripting: FakeTrackScripting,
    policy: Bool = true,
    testMode: Bool = true
) -> TrackOperationsController {
    TrackOperationsController(
        scripting: scripting,
        policyContextReady: { policy },
        testModeReady: { testMode },
        now: { Date(timeIntervalSince1970: 10) },
        sleep: { _ in }
    )
}

@Test("track operations preserve opaque identity through selection, rename, duplicate, and reorder")
func trackOperationsPreserveIdentity() throws {
    let scripting = FakeTrackScripting()
    let controller = controller(scripting: scripting)

    let observed = controller.observe(operationID: "observe")
    #expect(observed.status == .succeeded)
    #expect(observed.data.tracks.map(\.id) == ["track-a", "track-b"])

    let selected = controller.select(trackID: "track-b", operationID: "select", timeoutMilliseconds: 100)
    #expect(selected.status == .succeeded)
    #expect(selected.data.tracks.first(where: { $0.id == "track-b" })?.selected == true)

    let renamed = controller.rename(trackID: "track-b", name: "Lead Vocal", operationID: "rename", timeoutMilliseconds: 100)
    #expect(renamed.status == .succeeded)
    #expect(renamed.data.tracks.first(where: { $0.id == "track-b" })?.name == "Lead Vocal")

    let duplicated = controller.duplicate(trackID: "track-b", name: "Double", operationID: "duplicate", timeoutMilliseconds: 100)
    let duplicateID = try #require(duplicated.data.targetTrackID)
    #expect(duplicated.status == .succeeded)
    #expect(duplicateID != "track-b")
    #expect(duplicated.data.tracks.first(where: { $0.id == "track-b" })?.type == .audio)

    let reordered = controller.reorder(trackID: duplicateID, position: 1, operationID: "reorder", timeoutMilliseconds: 100)
    #expect(reordered.status == .succeeded)
    #expect(reordered.data.tracks.first?.id == duplicateID)
    #expect(reordered.data.tracks.contains(where: { $0.id == "track-b" }))
}

@Test("all supported track types are created with verified type, name, count, and selection")
func trackOperationsCreateSupportedTypes() {
    for (offset, type) in [LogicTrackType.softwareInstrument, .audio, .externalMIDI].enumerated() {
        let scripting = FakeTrackScripting()
        let result = controller(scripting: scripting).create(
            type: type,
            name: "Created \(offset)",
            operationID: "create-\(offset)",
            timeoutMilliseconds: 100
        )
        #expect(result.status == .succeeded)
        #expect(result.data.tracks.count == 3)
        #expect(result.data.tracks.contains(where: {
            $0.id == result.data.targetTrackID && $0.type == type && $0.name == "Created \(offset)" && $0.selected
        }))
    }
}

@Test("track mutations require managed policy context and active Exclusive Test Mode")
func trackOperationsRequireSafetyGates() {
    let noPolicy = controller(scripting: FakeTrackScripting(), policy: false).select(
        trackID: "track-a", operationID: "no-policy", timeoutMilliseconds: 100
    )
    #expect(noPolicy.data.failure == .projectPolicyMissing)
    #expect(!noPolicy.data.commandDispatched)

    let noTestMode = controller(scripting: FakeTrackScripting(), testMode: false).select(
        trackID: "track-a", operationID: "no-test-mode", timeoutMilliseconds: 100
    )
    #expect(noTestMode.data.failure == .testModeInactive)
    #expect(!noTestMode.data.commandDispatched)
}

@Test("track deletion requires confirmation and verifies Logic undo availability")
func trackDeletionRequiresConfirmationAndUndo() {
    let scripting = FakeTrackScripting()
    let trackController = controller(scripting: scripting)

    let denied = trackController.delete(
        trackID: "track-b", confirmed: false, operationID: "denied", timeoutMilliseconds: 100
    )
    #expect(denied.data.failure == .confirmationRequired)
    #expect((try? scripting.observeTracks().count) == 2)

    let deleted = trackController.delete(
        trackID: "track-b", confirmed: true, operationID: "delete", timeoutMilliseconds: 100
    )
    #expect(deleted.status == .succeeded)
    #expect(deleted.data.undoAvailable)
    #expect(!deleted.data.tracks.contains(where: { $0.id == "track-b" }))

    let noUndoScripting = FakeTrackScripting()
    noUndoScripting.undoAvailable = false
    let noUndo = controller(scripting: noUndoScripting).delete(
        trackID: "track-b", confirmed: true, operationID: "no-undo", timeoutMilliseconds: 100
    )
    #expect(noUndo.status == .partial)
    #expect(noUndo.data.failure == .undoUnavailable)
}

@Test("invalid names and positions fail before dispatch")
func trackOperationsRejectInvalidInputs() {
    let controller = controller(scripting: FakeTrackScripting())
    let rename = controller.rename(trackID: "track-a", name: " bad ", operationID: "rename", timeoutMilliseconds: 100)
    let reorder = controller.reorder(trackID: "track-a", position: 99, operationID: "reorder", timeoutMilliseconds: 100)

    #expect(rename.data.failure == .invalidName)
    #expect(reorder.data.failure == .invalidPosition)
    #expect(!rename.data.commandDispatched)
    #expect(!reorder.data.commandDispatched)
}
