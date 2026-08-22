import Foundation
import Testing

@testable import LogicBridgeCore

private final class FakeMIDIRegionScripting: LogicMIDIRegionScripting, @unchecked Sendable {
    private let lock = NSLock()
    private var regions: [MIDIRegionIdentity]
    var undoAvailable = true
    var playbackObserved = true
    var alterImportedVelocity = false

    init() {
        regions = [Self.makeRegion(
            id: "region-a",
            trackID: "track-a",
            name: "Verse",
            position: 0,
            length: 3_840,
            notes: [MIDINoteContent(
                pitch: 60,
                onset: MusicalTime(ticks: 0),
                duration: MusicalTime(ticks: 960),
                velocity: 100,
                channel: 1
            )]
        )]
    }

    func observeRegions() throws -> [MIDIRegionIdentity] { lock.withLock { regions } }

    func create(trackID: String, name: String, position: MusicalTime, length: MusicalTime, notes: [MIDINoteContent]) throws {
        lock.withLock {
            var imported = notes
            if alterImportedVelocity, !imported.isEmpty {
                let first = imported[0]
                imported[0] = MIDINoteContent(pitch: first.pitch, onset: first.onset, duration: first.duration, velocity: first.velocity - 1, channel: first.channel)
            }
            regions.append(Self.makeRegion(id: "region-\(regions.count + 1)", trackID: trackID, name: name, position: position.ticks, length: length.ticks, notes: imported))
        }
    }

    func rename(regionID: String, name: String) throws { try mutate(regionID) { Self.copy($0, name: name) } }
    func move(regionID: String, position: MusicalTime) throws { try mutate(regionID) { Self.copy($0, position: position) } }
    func resize(regionID: String, length: MusicalTime) throws { try mutate(regionID) { Self.copy($0, length: length) } }

    func duplicate(regionID: String, position: MusicalTime) throws {
        try lock.withLock {
            guard let source = regions.first(where: { $0.id == regionID }) else { throw LogicMIDIRegionScriptingError.regionNotFound }
            regions.append(Self.makeRegion(
                id: "region-\(regions.count + 1)", trackID: source.trackID, name: source.name,
                position: position.ticks, length: source.length.ticks, notes: source.notes.map(\.content)
            ))
        }
    }

    func split(regionID: String, position: MusicalTime) throws {
        try lock.withLock {
            guard let index = regions.firstIndex(where: { $0.id == regionID }) else { throw LogicMIDIRegionScriptingError.regionNotFound }
            let source = regions[index]
            let offset = position.ticks - source.position.ticks
            let leftNotes = source.notes.compactMap { note -> MIDINoteContent? in
                guard note.onset.ticks < offset else { return nil }
                let duration = min(note.duration.ticks, offset - note.onset.ticks)
                return MIDINoteContent(pitch: note.pitch, onset: note.onset, duration: MusicalTime(ticks: duration), velocity: note.velocity, channel: note.channel)
            }
            let rightNotes = source.notes.compactMap { note -> MIDINoteContent? in
                let absoluteEnd = note.onset.ticks + note.duration.ticks
                guard absoluteEnd > offset else { return nil }
                let onset = max(0, note.onset.ticks - offset)
                return MIDINoteContent(pitch: note.pitch, onset: MusicalTime(ticks: onset), duration: MusicalTime(ticks: absoluteEnd - max(note.onset.ticks, offset)), velocity: note.velocity, channel: note.channel)
            }
            regions[index] = Self.makeRegion(id: source.id, trackID: source.trackID, name: source.name, position: source.position.ticks, length: offset, notes: leftNotes)
            regions.append(Self.makeRegion(id: "region-\(regions.count + 1)", trackID: source.trackID, name: source.name, position: position.ticks, length: source.length.ticks - offset, notes: rightNotes))
        }
    }

    func updateNote(regionID: String, noteID: String, note: MIDINoteContent) throws {
        try mutate(regionID) { region in
            guard region.notes.contains(where: { $0.id == noteID }) else { return region }
            let notes = region.notes.map { $0.id == noteID ? MIDINoteIdentity(id: $0.id, content: note) : $0 }
            return Self.copy(region, notes: notes)
        }
    }

    func replaceNotes(regionID: String, notes: [MIDINoteContent]) throws {
        try mutate(regionID) { region in Self.copy(region, notes: Self.identify(notes)) }
    }

    func delete(regionID: String) throws {
        try lock.withLock {
            guard let index = regions.firstIndex(where: { $0.id == regionID }) else { throw LogicMIDIRegionScriptingError.regionNotFound }
            regions.remove(at: index)
        }
    }

    func deletionUndoAvailable() throws -> Bool { undoAvailable }
    func verifyPlayback(regionID: String, timeoutMilliseconds: Int) throws -> Bool {
        guard lock.withLock({ regions.contains(where: { $0.id == regionID }) }) else { throw LogicMIDIRegionScriptingError.regionNotFound }
        return playbackObserved
    }

    private func mutate(_ id: String, transform: (MIDIRegionIdentity) -> MIDIRegionIdentity) throws {
        try lock.withLock {
            guard let index = regions.firstIndex(where: { $0.id == id }) else { throw LogicMIDIRegionScriptingError.regionNotFound }
            regions[index] = transform(regions[index])
        }
    }

    private static func identify(_ notes: [MIDINoteContent]) -> [MIDINoteIdentity] {
        notes.enumerated().map { MIDINoteIdentity(id: "note-\($0.offset + 1)", content: $0.element) }
    }

    private static func makeRegion(id: String, trackID: String, name: String, position: Int64, length: Int64, notes: [MIDINoteContent]) -> MIDIRegionIdentity {
        MIDIRegionIdentity(
            id: id, trackID: trackID, name: name,
            position: MusicalTime(ticks: position), length: MusicalTime(ticks: length),
            notes: identify(notes), selected: true, active: true,
            observedAt: Date(timeIntervalSince1970: 2)
        )
    }

    private static func copy(
        _ region: MIDIRegionIdentity,
        name: String? = nil,
        position: MusicalTime? = nil,
        length: MusicalTime? = nil,
        notes: [MIDINoteIdentity]? = nil
    ) -> MIDIRegionIdentity {
        MIDIRegionIdentity(
            id: region.id, trackID: region.trackID, name: name ?? region.name,
            position: position ?? region.position, length: length ?? region.length,
            notes: notes ?? region.notes, selected: region.selected, active: region.active,
            observedAt: Date(timeIntervalSince1970: 3)
        )
    }
}

private func midiController(_ scripting: FakeMIDIRegionScripting, policy: Bool = true, testMode: Bool = true) -> MIDIRegionOperationsController {
    MIDIRegionOperationsController(
        scripting: scripting,
        policyContextReady: { policy },
        testModeReady: { testMode },
        now: { Date(timeIntervalSince1970: 10) },
        sleep: { _ in }
    )
}

private let fourBarNotes = [
    MIDINoteContent(pitch: 36, onset: MusicalTime(ticks: 0), duration: MusicalTime(ticks: 240), velocity: 127, channel: 10),
    MIDINoteContent(pitch: 60, onset: MusicalTime(ticks: 960), duration: MusicalTime(ticks: 1_920), velocity: 96, channel: 1),
    MIDINoteContent(pitch: 72, onset: MusicalTime(ticks: 14_400), duration: MusicalTime(ticks: 960), velocity: 48, channel: 2),
]

@Test("MIDI region create preserves all note fields and reports exact fidelity")
func midiRegionCreatePreservesFidelity() throws {
    let result = midiController(FakeMIDIRegionScripting()).create(
        trackID: "track-a", name: "Four Bars", position: MusicalTime(ticks: 3_840),
        length: MusicalTime(ticks: 15_360), notes: fourBarNotes,
        operationID: "create", timeoutMilliseconds: 100
    )

    #expect(result.status == .succeeded)
    #expect(result.data.exactFidelity)
    #expect(result.data.fidelityDifferences.isEmpty)
    let id = try #require(result.data.targetRegionID)
    let created = try #require(result.data.regions.first(where: { $0.id == id }))
    #expect(created.position == MusicalTime(ticks: 3_840))
    #expect(created.length == MusicalTime(ticks: 15_360))
    #expect(created.notes.map(\.content) == fourBarNotes)
}

@Test("MIDI create reports field-level import fidelity differences")
func midiRegionCreateReportsFidelityDifference() {
    let scripting = FakeMIDIRegionScripting()
    scripting.alterImportedVelocity = true
    let result = midiController(scripting).create(
        trackID: "track-a", name: "Changed", position: MusicalTime(ticks: 0),
        length: MusicalTime(ticks: 15_360), notes: fourBarNotes,
        operationID: "create-lossy", timeoutMilliseconds: 100
    )

    #expect(result.status == .partial)
    #expect(!result.data.exactFidelity)
    #expect(result.data.fidelityDifferences.contains(where: { $0.field == "notes[0].velocity" }))
}

@Test("MIDI region operations preserve region and note identities")
func midiRegionEditsPreserveIdentity() throws {
    let controller = midiController(FakeMIDIRegionScripting())
    #expect(controller.rename(regionID: "region-a", name: "Intro", operationID: "rename", timeoutMilliseconds: 100).status == .succeeded)
    #expect(controller.move(regionID: "region-a", position: MusicalTime(ticks: 3_840), operationID: "move", timeoutMilliseconds: 100).status == .succeeded)
    #expect(controller.resize(regionID: "region-a", length: MusicalTime(ticks: 7_680), operationID: "resize", timeoutMilliseconds: 100).status == .succeeded)

    let updatedContent = MIDINoteContent(pitch: 61, onset: MusicalTime(ticks: 120), duration: MusicalTime(ticks: 480), velocity: 77, channel: 3)
    let updated = controller.updateNote(regionID: "region-a", noteID: "note-1", note: updatedContent, operationID: "note", timeoutMilliseconds: 100)
    #expect(updated.status == .succeeded)
    #expect(updated.data.regions.first?.id == "region-a")
    #expect(updated.data.regions.first?.notes.first?.id == "note-1")
    #expect(updated.data.regions.first?.notes.first?.content == updatedContent)
}

@Test("MIDI region duplicate, split, bulk replace, playback, and delete verify outcomes")
func midiRegionRemainingOperationsVerifyOutcomes() throws {
    let controller = midiController(FakeMIDIRegionScripting())
    let duplicated = controller.duplicate(regionID: "region-a", position: MusicalTime(ticks: 7_680), operationID: "duplicate", timeoutMilliseconds: 100)
    let duplicateID = try #require(duplicated.data.targetRegionID)
    #expect(duplicated.status == .succeeded)
    #expect(duplicated.data.createdRegionIDs == [duplicateID])

    let replacement = [MIDINoteContent(
        pitch: 67, onset: MusicalTime(ticks: 480), duration: MusicalTime(ticks: 960), velocity: 88, channel: 4
    )]
    let replaced = controller.replaceNotes(regionID: duplicateID, notes: replacement, operationID: "replace", timeoutMilliseconds: 100)
    #expect(replaced.status == .succeeded)
    #expect(replaced.data.exactFidelity)
    #expect(replaced.data.regions.first(where: { $0.id == duplicateID })?.notes.map(\.content) == replacement)

    let split = controller.split(regionID: "region-a", position: MusicalTime(ticks: 1_920), operationID: "split", timeoutMilliseconds: 100)
    #expect(split.status == .succeeded)
    #expect(split.data.createdRegionIDs.count == 1)

    let playback = controller.verifyPlayback(regionID: "region-a", operationID: "playback", timeoutMilliseconds: 100)
    #expect(playback.status == .succeeded)
    #expect(playback.data.playbackVerified)

    let denied = controller.delete(regionID: duplicateID, confirmed: false, operationID: "denied", timeoutMilliseconds: 100)
    #expect(denied.data.failure == .confirmationRequired)
    let deleted = controller.delete(regionID: duplicateID, confirmed: true, operationID: "delete", timeoutMilliseconds: 100)
    #expect(deleted.status == .succeeded)
    #expect(deleted.data.undoAvailable)
}

@Test("MIDI mutations require managed policy, Test Mode, and valid 960 PPQ values")
func midiRegionOperationsEnforceSafetyAndValidation() {
    let noPolicy = midiController(FakeMIDIRegionScripting(), policy: false).move(
        regionID: "region-a", position: MusicalTime(ticks: 0), operationID: "policy", timeoutMilliseconds: 100
    )
    #expect(noPolicy.data.failure == .projectPolicyMissing)
    let noMode = midiController(FakeMIDIRegionScripting(), testMode: false).move(
        regionID: "region-a", position: MusicalTime(ticks: 0), operationID: "mode", timeoutMilliseconds: 100
    )
    #expect(noMode.data.failure == .testModeInactive)
    let invalidTime = midiController(FakeMIDIRegionScripting()).move(
        regionID: "region-a", position: MusicalTime(ticks: 0, ppq: 480), operationID: "time", timeoutMilliseconds: 100
    )
    #expect(invalidTime.data.failure == .invalidMusicalTime)
    #expect(!invalidTime.data.commandDispatched)
}
