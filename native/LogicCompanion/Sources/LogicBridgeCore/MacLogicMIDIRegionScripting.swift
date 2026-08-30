import AppKit
import ApplicationServices
import Foundation

struct LogicBBTValue: Equatable {
    let bars: Int64
    let beats: Int64
    let divisions: Int64
    let ticks: Int64

    static func position(from musicalTicks: Int64) -> Self {
        let barLength: Int64 = 3_840
        let beatLength: Int64 = 960
        let divisionLength: Int64 = 240
        let bar = musicalTicks / barLength
        let afterBar = musicalTicks % barLength
        let beat = afterBar / beatLength
        let afterBeat = afterBar % beatLength
        let division = afterBeat / divisionLength
        return Self(
            bars: bar + 1,
            beats: beat + 1,
            divisions: division + 1,
            ticks: (afterBeat % divisionLength) + 1
        )
    }

    static func duration(from musicalTicks: Int64) -> Self {
        let barLength: Int64 = 3_840
        let beatLength: Int64 = 960
        let divisionLength: Int64 = 240
        let bar = musicalTicks / barLength
        let afterBar = musicalTicks % barLength
        let beat = afterBar / beatLength
        let afterBeat = afterBar % beatLength
        return Self(
            bars: bar,
            beats: beat,
            divisions: afterBeat / divisionLength,
            ticks: afterBeat % divisionLength
        )
    }

    var positionTicks: Int64 {
        ((bars - 1) * 3_840) + ((beats - 1) * 960) + ((divisions - 1) * 240) + (ticks - 1)
    }

    var values: [Int64] { [bars, beats, divisions, ticks] }
}

/// Logic's bounded UI seam for MIDI regions. Region geometry is used only to
/// associate a region with its track; all public timing comes from Logic's
/// musical descriptions/Event Float, and note content is re-read from a
/// connector-owned temporary Standard MIDI File export.
public final class MacLogicMIDIRegionScripting: LogicMIDIRegionScripting, @unchecked Sendable {
    private struct RawRegion {
        let element: AXUIElement
        let trackID: String
        let name: String
        let position: MusicalTime
        let length: MusicalTime
        let selected: Bool
        let active: Bool
    }

    private struct Record {
        var id: String
        var element: AXUIElement
        var trackID: String
        var name: String
        var position: MusicalTime
        var length: MusicalTime
        var selected: Bool
        var active: Bool
        var notes: [MIDINoteIdentity]
        var notesObservedAt: Date?
    }

    private let lock = NSRecursiveLock()
    private let trackScripting: any LogicTrackScripting
    private var records: [Record] = []
    private var replacementRegionID: String?
    private var cachedTracksWindow: AXUIElement?
    private var cachedEventFloat: AXUIElement?
    private var cachedDocumentDirectory: URL?

    public init(trackScripting: any LogicTrackScripting) {
        self.trackScripting = trackScripting
    }

    public func observeRegions() throws -> [MIDIRegionIdentity] {
        try lock.withLock { try observeRegionsUnlocked() }
    }

    public func create(
        trackID: String,
        name: String,
        position: MusicalTime,
        length: MusicalTime,
        notes: [MIDINoteContent]
    ) throws {
        try lock.withLock {
            _ = try observeRegionsUnlocked()
            try importRegion(trackID: trackID, name: name, position: position, length: length, notes: notes)
        }
    }

#if DEBUG
    /// Narrow real-Logic acceptance seam for the remote Open panel. It avoids
    /// note observation (and therefore MIDI exports), then removes the region
    /// it imported before returning.
    func exerciseImportPanelForAcceptance(
        trackID: String,
        position: MusicalTime,
        length: MusicalTime,
        notes: [MIDINoteContent]
    ) throws {
        try lock.withLock {
            let application = try logicApplication(requireFocus: false)
            let tracks = try trackScripting.observeTracks()
            let beforeElements = try rawRegions(application: application, tracks: tracks).map(\.element)

            try importRegion(
                trackID: trackID,
                name: "LLM Import Panel Probe",
                position: position,
                length: length,
                notes: notes
            )

            let refreshedTracks = try trackScripting.observeTracks()
            let refreshedApplication = try logicApplication(requireFocus: false)
            let after = try rawRegions(application: refreshedApplication, tracks: refreshedTracks)
            guard let imported = after.first(where: { candidate in
                !beforeElements.contains(where: { CFEqual($0, candidate.element) })
            }) else {
                throw LogicMIDIRegionScriptingError.commandFailed
            }
            let cleanupRecord = Record(
                id: "acceptance-import", element: imported.element,
                trackID: imported.trackID, name: imported.name,
                position: imported.position, length: imported.length,
                selected: imported.selected, active: imported.active,
                notes: [], notesObservedAt: nil
            )
            try select(cleanupRecord)
            pressKey(51)
            Thread.sleep(forTimeInterval: 0.3)
        }
    }
#endif

    public func rename(regionID: String, name: String) throws {
        try lock.withLock {
            let record = try record(regionID)
            try editEventFloat(record: record, name: name)
            invalidate(regionID)
        }
    }

    public func move(regionID: String, position: MusicalTime) throws {
        try lock.withLock {
            try editEventFloat(record: record(regionID), position: position)
            invalidate(regionID)
        }
    }

    public func resize(regionID: String, length: MusicalTime) throws {
        try lock.withLock {
            try editEventFloat(record: record(regionID), length: length)
            invalidate(regionID)
        }
    }

    public func duplicate(regionID: String, position: MusicalTime) throws {
        try lock.withLock {
            let source = try record(regionID)
            try select(source)
            try performMenuItem(title: "Copy")
            try setPlayhead(position)
            try performMenuItem(title: "Paste")
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    public func split(regionID: String, position: MusicalTime) throws {
        try lock.withLock {
            try select(record(regionID))
            try setPlayhead(position)
            try performMenuItem(title: "Regions at Playhead")
            invalidate(regionID)
        }
    }

    public func updateNote(regionID: String, noteID: String, note: MIDINoteContent) throws {
        try lock.withLock {
            let source = try record(regionID)
            guard let index = source.notes.firstIndex(where: { $0.id == noteID }) else {
                throw LogicMIDIRegionScriptingError.noteNotFound
            }
            var notes = source.notes.map(\.content)
            notes[index] = note
            try replace(record: source, notes: notes)
        }
    }

    public func replaceNotes(regionID: String, notes: [MIDINoteContent]) throws {
        try lock.withLock { try replace(record: record(regionID), notes: notes) }
    }

    public func delete(regionID: String) throws {
        try lock.withLock {
            try select(record(regionID))
            pressKey(51)
            records.removeAll { $0.id == regionID }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    public func deletionUndoAvailable() throws -> Bool {
        let application = try logicApplication(requireFocus: false)
        guard let undo = descendants(application, maximum: 4_000).first(where: {
            attributeString($0, kAXRoleAttribute) == kAXMenuItemRole &&
                attributeString($0, kAXTitleAttribute)?.hasPrefix("Undo Delete") == true
        }) else { return false }
        return attributeBool(undo, kAXEnabledAttribute) != false
    }

    public func verifyPlayback(regionID: String, timeoutMilliseconds: Int) throws -> Bool {
        try lock.withLock {
            let application = try logicApplication(requireFocus: true)
            try select(record(regionID))
            try performMenuItem(title: "Play From Selected Region")
            let deadline = Date().addingTimeInterval(Double(max(0, timeoutMilliseconds)) / 1_000)
            var playing = false
            repeat {
                playing = descendants(application, maximum: 4_000).contains {
                    attributeString($0, kAXRoleAttribute) == kAXCheckBoxRole &&
                        attributeString($0, kAXTitleAttribute) == "Play" &&
                        attributeInt($0, kAXValueAttribute) == 1
                }
                if playing { break }
                Thread.sleep(forTimeInterval: 0.05)
            } while Date() < deadline
            if playing { pressKey(49) }
            return playing
        }
    }

    private func observeRegionsUnlocked() throws -> [MIDIRegionIdentity] {
        let application = try logicApplication(requireFocus: false)
        try rejectModal(application)
        let tracks = try trackScripting.observeTracks().sorted { $0.position < $1.position }
        let raw = try rawRegions(application: application, tracks: tracks)
        discoveryLog("tracks=\(tracks.count) rawRegions=\(raw.count)")
        var unmatched = records
        var next: [Record] = []
        let now = Date()

        for region in raw {
            let elementMatch = unmatched.firstIndex {
                CFEqual($0.element, region.element) && $0.trackID == region.trackID
            }
            let signatureMatches = unmatched.indices.filter {
                unmatched[$0].trackID == region.trackID &&
                    unmatched[$0].name == region.name &&
                    unmatched[$0].position == region.position &&
                    unmatched[$0].length == region.length
            }
            let index = elementMatch ?? (signatureMatches.count == 1 ? signatureMatches[0] : nil)
            var record: Record
            if let index {
                record = unmatched.remove(at: index)
                record.element = region.element
                record.trackID = region.trackID
                record.name = region.name
                record.position = region.position
                record.length = region.length
                record.selected = region.selected
                record.active = region.active
            } else {
                record = Record(
                    id: replacementRegionID ?? "region-\(UUID().uuidString.lowercased())",
                    element: region.element,
                    trackID: region.trackID,
                    name: region.name,
                    position: region.position,
                    length: region.length,
                    selected: region.selected,
                    active: region.active,
                    notes: [],
                    notesObservedAt: nil
                )
                replacementRegionID = nil
            }
            if record.notesObservedAt.map({ now.timeIntervalSince($0) > 0.25 }) != false {
                record.notes = try exportedNotes(for: record)
                record.notesObservedAt = Date()
            }
            next.append(record)
        }
        records = next
        let observedAt = Date()
        return next.sorted {
            ($0.position.ticks, $0.trackID, $0.name, $0.id) <
                ($1.position.ticks, $1.trackID, $1.name, $1.id)
        }.map {
            MIDIRegionIdentity(
                id: $0.id,
                trackID: $0.trackID,
                name: $0.name,
                position: $0.position,
                length: $0.length,
                notes: $0.notes,
                selected: $0.selected,
                active: $0.active,
                observedAt: observedAt
            )
        }
    }

    private func rawRegions(application: AXUIElement, tracks: [LogicTrackIdentity]) throws -> [RawRegion] {
        let applicationWindows = windows(application)
        discoveryLog("windows=\(applicationWindows.compactMap { attributeString($0, kAXTitleAttribute) })")
        let observedTracksWindow = applicationWindows.first(where: {
            attributeString($0, kAXTitleAttribute)?.hasSuffix(" - Tracks") == true
        })
        if let observedTracksWindow { cachedTracksWindow = observedTracksWindow }
        guard let tracksWindow = observedTracksWindow ?? cachedTracksWindow else {
            throw LogicMIDIRegionScriptingError.commandFailed
        }
        let all = descendants(tracksWindow, maximum: 20_000)
        let headers = all.compactMap { element -> (position: Int, frame: CGRect)? in
            guard attributeString(element, kAXRoleAttribute) == "AXLayoutItem",
                  let description = attributeString(element, kAXDescriptionAttribute),
                  let match = description.wholeMatch(of: /Track ([0-9]+) [“\"].+?[”\"](?:,.*)?/),
                  let position = Int(match.1), let frame = frame(element) else { return nil }
            return (position, frame)
        }
        var unique: [(Int, CGRect)] = []
        for header in headers where !unique.contains(where: { $0.0 == header.position }) {
            unique.append((header.position, header.frame))
        }
        return try all.compactMap { element -> RawRegion? in
            guard attributeString(element, kAXRoleAttribute) == "AXLayoutItem",
                  let help = attributeString(element, kAXHelpAttribute),
                  help.contains(", MIDI region."),
                  let description = attributeString(element, kAXDescriptionAttribute),
                  let regionFrame = frame(element),
                  let header = unique.first(where: { $0.1.contains(CGPoint(x: $0.1.midX, y: regionFrame.midY)) }),
                  let track = tracks.first(where: { $0.position == header.0 }) else { return nil }
            let times: (start: LogicBBTValue, end: LogicBBTValue)
            do { times = try parseRegionTimes(help) }
            catch {
                discoveryLog("failed region help=\(help)")
                throw error
            }
            let name = description.replacingOccurrences(
                of: #", (?:muted|looped|selected)(?:, (?:muted|looped|selected))*$"#,
                with: "",
                options: .regularExpression
            )
            return RawRegion(
                element: element,
                trackID: track.id,
                name: name,
                position: MusicalTime(ticks: times.start.positionTicks),
                length: MusicalTime(ticks: times.end.positionTicks - times.start.positionTicks),
                selected: attributeBool(element, kAXSelectedAttribute) == true,
                active: !description.localizedCaseInsensitiveContains(", muted")
            )
        }
    }

    private func parseRegionTimes(_ help: String) throws -> (start: LogicBBTValue, end: LogicBBTValue) {
        guard let match = help.firstMatch(of: /Region starts at (.+?) and ends at (.+?), MIDI region\./),
              let start = parsePosition(String(match.1)),
              let end = parsePosition(String(match.2)), end.positionTicks > start.positionTicks else {
            throw LogicMIDIRegionScriptingError.commandFailed
        }
        return (start, end)
    }

    private func parsePosition(_ text: String) -> LogicBBTValue? {
        func component(_ unit: String) -> Int64? {
            guard let range = text.range(of: #"[0-9]+ (?=\#(unit)s?\b)"#, options: .regularExpression) else { return nil }
            return Int64(text[range].dropLast())
        }
        guard let bars = component("bar") else { return nil }
        return LogicBBTValue(
            bars: bars,
            beats: component("beat") ?? 1,
            divisions: component("division") ?? 1,
            ticks: component("tick") ?? 1
        )
    }

    private func exportedNotes(for record: Record) throws -> [MIDINoteIdentity] {
        discoveryLog("export begin name=\(record.name) position=\(record.position.ticks)")
        // Modal save-panel sessions rebuild the arrangement's AX tree and
        // invalidate previously captured region elements, so re-resolve the
        // live element by signature before selecting.
        var liveRecord = record
        if let application = try? logicApplication(requireFocus: false),
           let tracks = try? trackScripting.observeTracks().sorted(by: { $0.position < $1.position }),
           let fresh = (try? rawRegions(application: application, tracks: tracks))?.first(where: {
               $0.trackID == record.trackID && $0.name == record.name &&
                   $0.position == record.position && $0.length == record.length
           }) {
            liveRecord.element = fresh.element
        }
        try select(liveRecord)
        let directory = try currentDocumentDirectory() ?? FileManager.default.temporaryDirectory
        // The save panel manages the .mid extension itself; setting a name
        // that already carries it produces mangled filenames.
        let stem = "llm-export-\(UUID().uuidString.lowercased())"
        try performMenuItem(title: "Selection as MIDI File…")
        discoveryLog("export menu dispatched")
        try completeSavePanel(filename: stem)
        let exportDeadline = Date().addingTimeInterval(10)
        var output: URL? = nil
        while output == nil, Date() < exportDeadline {
            let matches = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ))?.filter { $0.lastPathComponent.hasPrefix(stem) } ?? []
            output = matches.first
            if output == nil { Thread.sleep(forTimeInterval: 0.05) }
        }
        guard let output else {
            discoveryLog("export: file never appeared in \(directory.path)")
            throw LogicMIDIRegionScriptingError.commandFailed
        }
        defer { try? FileManager.default.removeItem(at: output) }
        discoveryLog("export saved bytes=\((try? Data(contentsOf: output).count) ?? -1)")
        let decoded = try StandardMIDIFile.decode(Data(contentsOf: output))
        var unmatched = record.notes
        return decoded.notes.map { note in
            let content = note.content
            let matches = unmatched.indices.filter { unmatched[$0].content == content }
            if matches.count == 1 { return unmatched.remove(at: matches[0]) }
            return MIDINoteIdentity(
                id: "note-\(UUID().uuidString.lowercased())",
                pitch: content.pitch,
                onset: content.onset,
                duration: content.duration,
                velocity: content.velocity,
                channel: content.channel
            )
        }
    }

    private func completeSavePanel(filename: String) throws {
        let application = try logicApplication(requireFocus: false)
        let panel = try waitForWindow(application: application) {
            attributeString($0, kAXTitleAttribute)?.hasPrefix("Save MIDI File as:") == true
        }
        var panelElements = descendants(panel, maximum: 2_000)
        guard let name = panelElements.first(where: {
            attributeString($0, kAXRoleAttribute) == kAXTextFieldRole &&
                attributeString($0, kAXValueAttribute)?.hasSuffix(".mid") == true
        }), AXUIElementSetAttributeValue(name, kAXValueAttribute as CFString, filename as CFTypeRef) == .success else {
            throw LogicMIDIRegionScriptingError.commandFailed
        }
        Thread.sleep(forTimeInterval: 0.3)
        panelElements = descendants(panel, maximum: 2_000)
        guard let save = panelElements.first(where: {
            attributeString($0, kAXRoleAttribute) == kAXButtonRole &&
                attributeString($0, kAXTitleAttribute) == "Save"
        }), AXUIElementPerformAction(save, kAXPressAction as CFString) == .success else {
            throw LogicMIDIRegionScriptingError.commandFailed
        }
        discoveryLog("save pressed")
    }

    private func importRegion(
        trackID: String,
        name: String,
        position: MusicalTime,
        length: MusicalTime,
        notes: [MIDINoteContent]
    ) throws {
        let beforeTracks = try trackScripting.observeTracks()
        let beforeElements = try rawRegions(
            application: logicApplication(requireFocus: false),
            tracks: beforeTracks
        ).map(\.element)
        // The Import Open panel opens at the user's home directory, so stage
        // the temporary Standard MIDI File in ~/Downloads, which the panel's
        // sidebar exposes directly (the document directory would require the
        // unusable go-to-folder sheet).
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
        let input = directory.appendingPathComponent("llm-import-\(UUID().uuidString.lowercased()).mid")
        defer {
            if ProcessInfo.processInfo.environment["LOGIC_MIDI_PRESERVE_STAGED_FILE"] != "1" {
                try? FileManager.default.removeItem(at: input)
            }
        }
        let identities = notes.enumerated().map { index, note in
            MIDINoteIdentity(
                id: "import-\(index)", pitch: note.pitch, onset: note.onset,
                duration: note.duration, velocity: note.velocity, channel: note.channel
            )
        }
        try StandardMIDIFile.encode(name: name, lengthTicks: length.ticks, notes: identities).write(to: input, options: .atomic)
        discoveryLog("import: staged \(input.lastPathComponent)")
        try trackScripting.select(trackID: trackID)
        discoveryLog("import: track selected")
        try setPlayhead(position)
        discoveryLog("import: playhead set")
        try performMenuItem(title: "MIDI File…")
        discoveryLog("import: menu dispatched")
        try completeOpenPanel(path: input.path)
        Thread.sleep(forTimeInterval: 0.5)

        let afterTracks = try trackScripting.observeTracks()
        let application = try logicApplication(requireFocus: false)
        let after = try rawRegions(application: application, tracks: afterTracks)
        guard let created = after.first(where: { candidate in
            !beforeElements.contains(where: { CFEqual($0, candidate.element) })
        }) else { throw LogicMIDIRegionScriptingError.commandFailed }
        if created.trackID != trackID {
            try moveRegionVertically(created, toTrackID: trackID, application: application, tracks: afterTracks)
        }
        let temporary = Record(
            id: "region-\(UUID().uuidString.lowercased())", element: created.element,
            trackID: trackID, name: created.name, position: created.position, length: created.length,
            selected: created.selected, active: created.active, notes: [], notesObservedAt: nil
        )
        try editEventFloat(record: temporary, name: name, position: position, length: length)
        let addedTracks = afterTracks.filter { candidate in !beforeTracks.contains(where: { $0.id == candidate.id }) }
        for track in addedTracks where track.id != trackID {
            try? trackScripting.delete(trackID: track.id)
        }
    }

    /// Resolve the staged file through the Downloads sidebar item exposed by
    /// the remote Import panel, then confirm the MIDI import.
    private func completeOpenPanel(path: String) throws {
        let application = try logicApplication(requireFocus: false)
        let panel = try waitForWindow(application: application) { window in
            let title = attributeString(window, kAXTitleAttribute) ?? ""
            if title.localizedCaseInsensitiveContains("midi") ||
                title.localizedCaseInsensitiveContains("import") { return true }
            return descendants(window, maximum: 2_000).contains {
                attributeString($0, kAXRoleAttribute) == kAXButtonRole &&
                    ["Open", "Import"].contains(attributeString($0, kAXTitleAttribute) ?? "")
            }
        }
        discoveryLog("open panel found")
        _ = AXUIElementPerformAction(panel, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(panel, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(panel, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.2)
        let stagedFile = URL(fileURLWithPath: path)
        let downloads = descendants(panel, maximum: 2_000).filter {
            attributeString($0, kAXRoleAttribute) == kAXStaticTextRole &&
                [
                    attributeString($0, kAXTitleAttribute),
                    attributeString($0, kAXValueAttribute),
                ].contains("Downloads") && frame($0) != nil
        }.min { (frame($0)?.minX ?? .greatestFiniteMagnitude) <
            (frame($1)?.minX ?? .greatestFiniteMagnitude) }
        guard let downloads, let downloadsFrame = frame(downloads) else {
            discoveryLog("open panel: Downloads sidebar item missing")
            throw LogicMIDIRegionScriptingError.commandFailed
        }
        click(at: CGPoint(x: downloadsFrame.midX, y: downloadsFrame.midY))
        discoveryLog("open panel: Downloads sidebar clicked")

        let row = try waitForElement(root: panel) {
            [kAXStaticTextRole, kAXTextFieldRole].contains(
                attributeString($0, kAXRoleAttribute) ?? ""
            ) &&
                attributeString($0, kAXValueAttribute) == stagedFile.lastPathComponent
        }
        guard let rowGroup = elementAttribute(row, kAXParentAttribute),
              let list = elementAttribute(rowGroup, kAXParentAttribute) else {
            discoveryLog("open panel: staged file list hierarchy missing")
            throw LogicMIDIRegionScriptingError.commandFailed
        }
        _ = AXUIElementSetAttributeValue(
            list, kAXSelectedChildrenAttribute as CFString, [rowGroup] as CFArray
        )
        let confirm = try waitForElement(root: panel) {
            attributeString($0, kAXRoleAttribute) == kAXButtonRole &&
                ["Open", "Import"].contains(attributeString($0, kAXTitleAttribute) ?? "") &&
                attributeBool($0, kAXEnabledAttribute) == true
        }
        guard AXUIElementPerformAction(confirm, kAXPressAction as CFString) == .success else {
            discoveryLog("open panel: enabled confirmation button could not be pressed")
            throw LogicMIDIRegionScriptingError.commandFailed
        }
        discoveryLog("open panel: staged file selected and confirmed")
        let dismissalDeadline = Date().addingTimeInterval(10)
        while windows(application).contains(where: { CFEqual($0, panel) }),
              Date() < dismissalDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !windows(application).contains(where: { CFEqual($0, panel) }) else {
            discoveryLog("open panel: confirmation did not dismiss panel")
            throw LogicMIDIRegionScriptingError.commandFailed
        }
        let tempoPromptDeadline = Date().addingTimeInterval(3)
        var tempoPrompt: AXUIElement?
        repeat {
            tempoPrompt = windows(application).first { window in
                descendants(window, maximum: 500).contains {
                    attributeString($0, kAXValueAttribute) == "Also import tempo information?"
                }
            }
            if tempoPrompt == nil { Thread.sleep(forTimeInterval: 0.05) }
        } while tempoPrompt == nil && Date() < tempoPromptDeadline
        if let tempoPrompt {
            guard let no = descendants(tempoPrompt, maximum: 500).first(where: {
                attributeString($0, kAXRoleAttribute) == kAXButtonRole &&
                    attributeString($0, kAXTitleAttribute) == "No" &&
                    attributeBool($0, kAXEnabledAttribute) != false
            }), AXUIElementPerformAction(no, kAXPressAction as CFString) == .success else {
                discoveryLog("open panel: tempo prompt No button missing")
                throw LogicMIDIRegionScriptingError.commandFailed
            }
            let tempoDismissalDeadline = Date().addingTimeInterval(5)
            while windows(application).contains(where: { CFEqual($0, tempoPrompt) }),
                  Date() < tempoDismissalDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard !windows(application).contains(where: { CFEqual($0, tempoPrompt) }) else {
                discoveryLog("open panel: tempo prompt did not dismiss")
                throw LogicMIDIRegionScriptingError.commandFailed
            }
            discoveryLog("open panel: tempo import declined")
        }
        discoveryLog("open panel confirmed")
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func replace(record source: Record, notes: [MIDINoteContent]) throws {
        try importRegion(
            trackID: source.trackID, name: source.name, position: source.position,
            length: source.length, notes: notes
        )
        try select(source)
        pressKey(51)
        replacementRegionID = source.id
        records.removeAll { $0.id == source.id }
    }

    private func moveRegionVertically(
        _ region: RawRegion,
        toTrackID trackID: String,
        application: AXUIElement,
        tracks: [LogicTrackIdentity]
    ) throws {
        guard let target = tracks.first(where: { $0.id == trackID }),
              let sourceFrame = frame(region.element),
              let header = descendants(application, maximum: 20_000).first(where: {
                  guard attributeString($0, kAXRoleAttribute) == "AXLayoutItem",
                        let description = attributeString($0, kAXDescriptionAttribute) else { return false }
                  return description.hasPrefix("Track \(target.position) “") || description.hasPrefix("Track \(target.position) \"")
              }), let targetFrame = frame(header) else { throw LogicMIDIRegionScriptingError.trackNotFound }
        let start = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let finish = CGPoint(x: sourceFrame.midX, y: targetFrame.midY)
        try drag(from: start, to: finish)
    }

    private func editEventFloat(
        record: Record,
        name: String? = nil,
        position: MusicalTime? = nil,
        length: MusicalTime? = nil
    ) throws {
        try select(record)
        let application = try logicApplication(requireFocus: true)
        var float = eventFloat(application)
        if float == nil {
            guard let item = descendants(application, maximum: 4_000).first(where: {
                attributeString($0, kAXRoleAttribute) == kAXMenuItemRole &&
                    attributeString($0, kAXTitleAttribute)?.hasSuffix("Event Float") == true
            }), AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
                throw LogicMIDIRegionScriptingError.commandFailed
            }
            float = try waitForWindow(application: application) {
                attributeString($0, kAXTitleAttribute)?.hasSuffix("Event List") == true &&
                    (frame($0)?.height ?? 1_000) < 100
            }
        }
        guard let float else { throw LogicMIDIRegionScriptingError.commandFailed }
        let elements = descendants(float, maximum: 500)
        let groups = elements.filter {
            attributeString($0, kAXRoleAttribute) == kAXGroupRole &&
                descendants($0, maximum: 20).filter { attributeString($0, kAXRoleAttribute) == kAXSliderRole }.count == 4
        }.sorted { (frame($0)?.minX ?? 0) < (frame($1)?.minX ?? 0) }
        if let position {
            guard let group = groups.first else { throw LogicMIDIRegionScriptingError.commandFailed }
            try setSegments(group, values: LogicBBTValue.position(from: position.ticks).values)
        }
        if let length {
            guard let group = groups.last, groups.count >= 2 else { throw LogicMIDIRegionScriptingError.commandFailed }
            try setSegments(group, values: LogicBBTValue.duration(from: length.ticks).values)
        }
        if let name {
            guard let field = elements.first(where: {
                attributeString($0, kAXRoleAttribute) == kAXTextFieldRole &&
                    attributeString($0, kAXValueAttribute) == record.name
            }), AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, name as CFTypeRef) == .success else {
                throw LogicMIDIRegionScriptingError.commandFailed
            }
            pressKey(36)
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func setSegments(_ group: AXUIElement, values: [Int64]) throws {
        let sliders = descendants(group, maximum: 20).filter {
            attributeString($0, kAXRoleAttribute) == kAXSliderRole
        }.sorted {
            (attributeString($0, kAXDescriptionAttribute) ?? "") <
                (attributeString($1, kAXDescriptionAttribute) ?? "")
        }
        // Condensed LCD modes expose fewer segments (e.g. bar/beat only);
        // set the leading components that are present.
        guard sliders.count <= values.count, !sliders.isEmpty else {
            discoveryLog("setSegments: sliders=\(sliders.count) values=\(values.count)")
            throw LogicMIDIRegionScriptingError.commandFailed
        }
        for (slider, value) in zip(sliders, values) {
            guard AXUIElementSetAttributeValue(slider, kAXValueAttribute as CFString, NSNumber(value: value)) == .success else {
                throw LogicMIDIRegionScriptingError.commandFailed
            }
        }
        pressKey(36)
    }

    private func setPlayhead(_ position: MusicalTime) throws {
        let application = try logicApplication(requireFocus: true)
        guard let display = descendants(application, maximum: 4_000).first(where: {
            attributeString($0, kAXDescriptionAttribute) == "Playhead Position" &&
                attributeString($0, kAXHelpAttribute)?.contains("Bars") == true
        }) else { throw LogicMIDIRegionScriptingError.commandFailed }
        try setSegments(display, values: LogicBBTValue.position(from: position.ticks).values)
    }

    private func eventFloat(_ application: AXUIElement) -> AXUIElement? {
        let observed = windows(application).first {
            attributeString($0, kAXTitleAttribute)?.hasSuffix("Event List") == true &&
                (frame($0)?.height ?? 1_000) < 100
        }
        if let observed { cachedEventFloat = observed }
        return observed ?? cachedEventFloat
    }

    private func select(_ record: Record) throws {
        // Region AXPress is inconsistent, but Logic exposes AXSelected as a
        // settable attribute even when its readback remains false. Prefer that
        // semantic selection because floating plug-in windows can obscure a
        // region's screen coordinates; retain a real click as the fallback.
        let application = try logicApplication(requireFocus: true)
        if let cached = cachedTracksWindow {
            let raiseStatus = AXUIElementPerformAction(cached, kAXRaiseAction as CFString)
            let mainStatus = AXUIElementSetAttributeValue(
                cached, kAXMainAttribute as CFString, kCFBooleanTrue
            )
            let focusedStatus = AXUIElementSetAttributeValue(
                cached, kAXFocusedAttribute as CFString, kCFBooleanTrue
            )
            discoveryLog(
                "select: tracks raise=\(raiseStatus.rawValue) main=\(mainStatus.rawValue) " +
                    "focus=\(focusedStatus.rawValue)"
            )
            Thread.sleep(forTimeInterval: 0.2)
        }
        var pressStatus: AXError = .failure
        var selectedStatus: AXError = .failure
        for _ in 1 ... 3 {
            pressStatus = AXUIElementPerformAction(record.element, kAXPressAction as CFString)
            selectedStatus = AXUIElementSetAttributeValue(
                record.element, kAXSelectedAttribute as CFString, kCFBooleanTrue
            )
            Thread.sleep(forTimeInterval: 0.2)
            if attributeBool(record.element, kAXSelectedAttribute) == true { break }
        }
        if attributeBool(record.element, kAXSelectedAttribute) != true {
            guard let regionFrame = frame(record.element) else {
                discoveryLog("select: region frame unavailable")
                throw LogicMIDIRegionScriptingError.regionNotFound
            }
            let applicationWindows = windows(application)
            let frontWindows: [AXUIElement]
            if let tracksWindow = cachedTracksWindow,
               let tracksIndex = applicationWindows.firstIndex(where: { CFEqual($0, tracksWindow) }) {
                frontWindows = Array(applicationWindows.prefix(upTo: tracksIndex))
            } else {
                frontWindows = []
            }
            let candidates = [
                CGPoint(x: regionFrame.midX, y: regionFrame.midY),
                CGPoint(x: regionFrame.minX + 4, y: regionFrame.midY),
                CGPoint(x: regionFrame.maxX - 4, y: regionFrame.midY),
                CGPoint(x: regionFrame.minX + regionFrame.width * 0.25, y: regionFrame.midY),
                CGPoint(x: regionFrame.minX + regionFrame.width * 0.75, y: regionFrame.midY),
            ]
            var frontWindowFrames = frontWindows.compactMap(frame)
            var visiblePoint = candidates.first(where: { point in
                !frontWindowFrames.contains(where: { $0.contains(point) })
            })
            if visiblePoint == nil {
                var closedObstruction = false
                for window in frontWindows where attributeBool(window, kAXModalAttribute) != true {
                    guard let windowFrame = frame(window), candidates.allSatisfy(windowFrame.contains),
                          let closeButton = elementAttribute(window, kAXCloseButtonAttribute),
                          AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success else {
                        continue
                    }
                    discoveryLog("select: closed obstructing window \(attributeString(window, kAXTitleAttribute) ?? "untitled")")
                    closedObstruction = true
                }
                if closedObstruction {
                    Thread.sleep(forTimeInterval: 0.3)
                    _ = AXUIElementPerformAction(record.element, kAXPressAction as CFString)
                    _ = AXUIElementSetAttributeValue(
                        record.element, kAXSelectedAttribute as CFString, kCFBooleanTrue
                    )
                    Thread.sleep(forTimeInterval: 0.2)
                    let updatedWindows = windows(application)
                    if let tracksWindow = cachedTracksWindow,
                       let tracksIndex = updatedWindows.firstIndex(where: { CFEqual($0, tracksWindow) }) {
                        frontWindowFrames = updatedWindows.prefix(upTo: tracksIndex).compactMap(frame)
                    } else {
                        frontWindowFrames = []
                    }
                    visiblePoint = candidates.first(where: { point in
                        !frontWindowFrames.contains(where: { $0.contains(point) })
                    })
                }
            }
            if attributeBool(record.element, kAXSelectedAttribute) != true,
               let visiblePoint {
                click(at: visiblePoint)
            } else if attributeBool(record.element, kAXSelectedAttribute) != true {
                discoveryLog("select: region fully obscured by a floating window")
            }
        }
        Thread.sleep(forTimeInterval: 0.2)
        discoveryLog(
            "select: press=\(pressStatus.rawValue) set-selected=\(selectedStatus.rawValue) " +
                "selected-read=\(attributeBool(record.element, kAXSelectedAttribute) ?? false)"
        )
    }

    /// Menu bars of background applications are not exposed through
    /// Accessibility, so Logic must be active before menu dispatch.
    /// Activation through the Apple Event works from background helper
    /// processes where NSRunningApplication.activate does not.
    private func activateLogic() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"com.apple.logic10\" to activate"]
        try? process.run()
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.logic10" {
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            launcher.arguments = ["-a", "Logic Pro"]
            try? launcher.run()
            let launcherDeadline = Date().addingTimeInterval(5)
            while launcher.isRunning, Date() < launcherDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if launcher.isRunning { launcher.terminate() }
        }
        let settleDeadline = Date().addingTimeInterval(5)
        while NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.logic10",
              Date() < settleDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func performMenuItem(title: String) throws {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.logic10" {
            activateLogic()
        }
        let application = try logicApplication(requireFocus: true)
        try rejectModal(application)
        // Logic validates dynamic items only while their top-level menu is
        // open. A dormant application-wide AX walk can therefore report an
        // item as absent or disabled even when the current selection supports
        // it. Open each top-level menu before searching its populated subtree.
        var pressed = false
        var lastStatus: AXError = .attributeUnsupported
        var openedMenu: AXUIElement?
        for attempt in 1 ... 5 {
            let menuBarItems = descendants(application, maximum: 500).filter {
                attributeString($0, kAXRoleAttribute) == kAXMenuBarItemRole &&
                    attributeBool($0, kAXEnabledAttribute) != false
            }
            for menuBarItem in menuBarItems {
                guard AXUIElementPerformAction(menuBarItem, kAXPressAction as CFString) == .success else {
                    continue
                }
                Thread.sleep(forTimeInterval: 0.1)
                if let item = descendants(menuBarItem, maximum: 4_000).first(where: {
                    attributeString($0, kAXRoleAttribute) == kAXMenuItemRole &&
                        attributeString($0, kAXTitleAttribute) == title &&
                        attributeBool($0, kAXEnabledAttribute) != false
                }) {
                    lastStatus = AXUIElementPerformAction(item, kAXPressAction as CFString)
                    if lastStatus == .success {
                        openedMenu = descendants(menuBarItem, maximum: 50).first {
                            attributeString($0, kAXRoleAttribute) == kAXMenuRole
                        }
                        pressed = true
                        break
                    }
                }
                pressKey(53)
            }
            if pressed { break }
            discoveryLog("menu \(title): attempt \(attempt) missed (walk or press)")
            Thread.sleep(forTimeInterval: 0.4)
        }
        guard pressed else {
            discoveryLog("menu \(title): item missing or press failed status=\(lastStatus.rawValue)")
            throw LogicMIDIRegionScriptingError.commandFailed
        }
        if let openedMenu {
            _ = AXUIElementPerformAction(openedMenu, "AXCancel" as CFString)
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func waitForWindow(
        application: AXUIElement,
        predicate: (AXUIElement) -> Bool
    ) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            let candidates = [focusedWindow(application)].compactMap { $0 } + windows(application)
            if let value = candidates.first(where: predicate) { return value }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        throw LogicMIDIRegionScriptingError.commandFailed
    }

    private func waitForElement(
        root: AXUIElement,
        predicate: (AXUIElement) -> Bool
    ) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(3)
        repeat {
            if let value = descendants(root, maximum: 2_000).first(where: predicate) { return value }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        throw LogicMIDIRegionScriptingError.commandFailed
    }

    private func logicApplication(requireFocus: Bool) throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw LogicMIDIRegionScriptingError.accessibilityUnavailable }
        guard let logic = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.logic10" }) else {
            throw LogicMIDIRegionScriptingError.logicNotRunning
        }
        if requireFocus, NSWorkspace.shared.frontmostApplication?.processIdentifier != logic.processIdentifier {
            activateLogic()
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != logic.processIdentifier {
                throw LogicMIDIRegionScriptingError.logicNotFocused
            }
        }
        return AXUIElementCreateApplication(logic.processIdentifier)
    }

    private func rejectModal(_ application: AXUIElement) throws {
        if windows(application).contains(where: { attributeBool($0, kAXModalAttribute) == true }) {
            throw LogicMIDIRegionScriptingError.dialogPresented
        }
    }

    private func record(_ id: String) throws -> Record {
        guard let value = records.first(where: { $0.id == id }) else {
            throw LogicMIDIRegionScriptingError.regionNotFound
        }
        return value
    }

    private func invalidate(_ id: String) {
        if let index = records.firstIndex(where: { $0.id == id }) { records[index].notesObservedAt = nil }
    }

    private func descendants(_ root: AXUIElement, maximum: Int) -> [AXUIElement] {
        var output: [AXUIElement] = []
        var queue = [root]
        while let element = queue.first, output.count < maximum {
            queue.removeFirst()
            output.append(element)
            queue.append(contentsOf: arrayAttribute(element, kAXChildrenAttribute))
        }
        return output
    }

    private func windows(_ application: AXUIElement) -> [AXUIElement] {
        arrayAttribute(application, kAXWindowsAttribute)
    }

    private func focusedWindow(_ application: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func arrayAttribute(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func attributeString(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func attributeBool(_ element: AXUIElement, _ name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private func attributeInt(_ element: AXUIElement, _ name: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
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

    /// Directory of the frontmost open Logic document. The export save panel
    /// defaults to this directory, so exports land there without driving the
    /// unreliable go-to-folder navigation sheet.
    private func currentDocumentDirectory() throws -> URL? {
        if let cached = cachedDocumentDirectory { return cached }
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "com.apple.logic10"
        }) else { return nil }
        let source = """
        with timeout of 5 seconds
        tell application id "com.apple.logic10"
            if (count documents) is 0 then return ""
            return (path of front document as text)
        end tell
        end timeout
        """
        // osascript keeps the Apple Event reply pump out of this process;
        // in-process NSAppleScript can deadlock when the calling thread
        // drains the main queue. Retry briefly: Logic may still be settling
        // after a modal save-panel session.
        for _ in 0..<20 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            guard (try? process.run()) != nil else { return nil }
            let deadline = Date().addingTimeInterval(10)
            var output = Data()
            while Date() < deadline {
                let chunk = pipe.fileHandleForReading.availableData
                if !chunk.isEmpty { output.append(chunk) }
                if !process.isRunning { break }
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                process.terminate()
            } else if var path = String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !path.isEmpty, path != "missing value" {
                if !path.hasPrefix("/") {
                    path = path.hasPrefix("Macintosh HD:")
                        ? String(path.dropFirst("Macintosh HD:".count)) : path
                    path = "/" + path.replacingOccurrences(of: ":", with: "/")
                }
                let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
                cachedDocumentDirectory = directory
                return directory
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        discoveryLog("currentDocumentDirectory: exhausted retries")
        return nil
    }

    /// Synthetic CGEvents do not reach Logic's remotely-hosted save/open panels,
    /// so key presses are delivered through System Events keystrokes, which
    /// target the frontmost application's focused element.
    private func pressKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        var modifiers: [String] = []
        if flags.contains(.maskCommand) { modifiers.append("command down") }
        if flags.contains(.maskShift) { modifiers.append("shift down") }
        if flags.contains(.maskAlternate) { modifiers.append("option down") }
        if flags.contains(.maskControl) { modifiers.append("control down") }
        let modifierList = modifiers.isEmpty ? "" : " using {" + modifiers.joined(separator: ", ") + "}"
        let source = "tell application \"System Events\" to key code \(Int(code))\(modifierList)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { process.terminate() }
        } catch {
            discoveryLog("pressKey: \(error.localizedDescription)")
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func typeText(_ text: String) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"System Events\" to keystroke \"\(escaped)\"",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { process.terminate() }
        } catch {
            discoveryLog("typeText: \(error.localizedDescription)")
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func click(at point: CGPoint) {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return
        }
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.06)
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func drag(from start: CGPoint, to finish: CGPoint) throws {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: finish, mouseButton: .left) else {
            throw LogicMIDIRegionScriptingError.commandFailed
        }
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
        for step in 1 ... 12 {
            let progress = CGFloat(step) / 12
            let point = CGPoint(
                x: start.x + ((finish.x - start.x) * progress),
                y: start.y + ((finish.y - start.y) * progress)
            )
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.02)
        }
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func discoveryLog(_ message: String) {
        if ProcessInfo.processInfo.environment["LOGIC_MIDI_ADAPTER_DISCOVERY"] == "1" {
            print("MIDI_ADAPTER_STAGE \(message)")
        }
    }
}
