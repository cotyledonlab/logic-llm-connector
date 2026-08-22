import Foundation

public enum StandardMIDIFileError: Error, Equatable {
    case invalidHeader
    case unsupportedFormat(Int)
    case unsupportedTimeDivision
    case malformedTrack
    case invalidNote
    case inexactTimeScaling
}

public struct StandardMIDISequence: Sendable, Equatable {
    public let name: String?
    public let ppq: Int
    public let lengthTicks: Int64
    public let notes: [MIDINoteIdentity]

    public init(name: String?, ppq: Int, lengthTicks: Int64, notes: [MIDINoteIdentity]) {
        self.name = name
        self.ppq = ppq
        self.lengthTicks = lengthTicks
        self.notes = notes
    }
}

/// A deliberately small Standard MIDI File codec for deterministic region interchange.
/// It writes format 0 and reads format 0/1 note, track-name, and end-of-track events.
public enum StandardMIDIFile {
    private struct Event {
        let tick: Int64
        let priority: Int
        let bytes: [UInt8]
    }

    public static func encode(
        name: String?,
        ppq: Int = logicMusicalTimePPQ,
        lengthTicks: Int64,
        notes: [MIDINoteIdentity]
    ) throws -> Data {
        guard (1 ... 0x7fff).contains(ppq), lengthTicks > 0 else {
            throw StandardMIDIFileError.unsupportedTimeDivision
        }
        try notes.forEach {
            try validate($0)
            guard $0.onset.ppq == ppq else { throw StandardMIDIFileError.inexactTimeScaling }
        }

        var events: [Event] = []
        if let name, !name.isEmpty {
            let utf8 = Array(name.utf8)
            events.append(Event(tick: 0, priority: 0, bytes: [0xff, 0x03] + variableLength(utf8.count) + utf8))
        }
        for note in notes {
            let channel = UInt8(note.channel - 1)
            events.append(Event(
                tick: note.onset.ticks,
                priority: 2,
                bytes: [0x90 | channel, UInt8(note.pitch), UInt8(note.velocity)]
            ))
            events.append(Event(
                tick: note.onset.ticks + note.duration.ticks,
                priority: 1,
                bytes: [0x80 | channel, UInt8(note.pitch), 0]
            ))
        }
        events.sort {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.bytes.lexicographicallyPrecedes($1.bytes)
        }

        var track: [UInt8] = []
        var previousTick: Int64 = 0
        for event in events {
            track += variableLength(Int(event.tick - previousTick))
            track += event.bytes
            previousTick = event.tick
        }
        let endTick = max(lengthTicks, previousTick)
        track += variableLength(Int(endTick - previousTick))
        track += [0xff, 0x2f, 0x00]

        var output: [UInt8] = Array("MThd".utf8)
        output += bigEndian(UInt32(6))
        output += bigEndian(UInt16(0))
        output += bigEndian(UInt16(1))
        output += bigEndian(UInt16(ppq))
        output += Array("MTrk".utf8)
        output += bigEndian(UInt32(track.count))
        output += track
        return Data(output)
    }

    public static func decode(_ data: Data, targetPPQ: Int = logicMusicalTimePPQ) throws -> StandardMIDISequence {
        let bytes = Array(data)
        guard bytes.count >= 14, String(bytes: bytes[0 ..< 4], encoding: .ascii) == "MThd" else {
            throw StandardMIDIFileError.invalidHeader
        }
        let headerLength = Int(readUInt32(bytes, at: 4))
        guard headerLength >= 6, bytes.count >= 8 + headerLength else { throw StandardMIDIFileError.invalidHeader }
        let format = Int(readUInt16(bytes, at: 8))
        guard format == 0 || format == 1 else { throw StandardMIDIFileError.unsupportedFormat(format) }
        let trackCount = Int(readUInt16(bytes, at: 10))
        let sourcePPQ = Int(readUInt16(bytes, at: 12))
        guard sourcePPQ > 0, sourcePPQ & 0x8000 == 0, targetPPQ > 0 else {
            throw StandardMIDIFileError.unsupportedTimeDivision
        }

        var cursor = 8 + headerLength
        var decodedName: String?
        var decodedNotes: [(tick: Int64, pitch: Int, velocity: Int, channel: Int, duration: Int64)] = []
        var maximumTick: Int64 = 0
        for _ in 0 ..< trackCount {
            guard cursor + 8 <= bytes.count,
                  String(bytes: bytes[cursor ..< cursor + 4], encoding: .ascii) == "MTrk" else {
                throw StandardMIDIFileError.malformedTrack
            }
            let length = Int(readUInt32(bytes, at: cursor + 4))
            cursor += 8
            guard cursor + length <= bytes.count else { throw StandardMIDIFileError.malformedTrack }
            let decoded = try decodeTrack(Array(bytes[cursor ..< cursor + length]))
            if decodedName == nil { decodedName = decoded.name }
            maximumTick = max(maximumTick, decoded.lengthTicks)
            decodedNotes += decoded.notes
            cursor += length
        }

        let scale: (Int64) throws -> Int64 = { tick in
            let product = tick.multipliedReportingOverflow(by: Int64(targetPPQ))
            guard !product.overflow, product.partialValue % Int64(sourcePPQ) == 0 else {
                throw StandardMIDIFileError.inexactTimeScaling
            }
            return product.partialValue / Int64(sourcePPQ)
        }
        let ordered = decodedNotes.sorted {
            ($0.tick, $0.pitch, $0.channel, $0.duration, $0.velocity) <
                ($1.tick, $1.pitch, $1.channel, $1.duration, $1.velocity)
        }
        let notes = try ordered.enumerated().map { offset, note in
            MIDINoteIdentity(
                id: "note-\(offset + 1)",
                pitch: note.pitch,
                onset: MusicalTime(ticks: try scale(note.tick), ppq: targetPPQ),
                duration: MusicalTime(ticks: try scale(note.duration), ppq: targetPPQ),
                velocity: note.velocity,
                channel: note.channel
            )
        }
        return StandardMIDISequence(
            name: decodedName,
            ppq: targetPPQ,
            lengthTicks: try scale(maximumTick),
            notes: notes
        )
    }

    private static func validate(_ note: MIDINoteIdentity) throws {
        guard (0 ... 127).contains(note.pitch), (1 ... 127).contains(note.velocity),
              (1 ... 16).contains(note.channel), note.onset.ticks >= 0,
              note.duration.ticks > 0, note.onset.ppq > 0,
              note.duration.ppq == note.onset.ppq else { throw StandardMIDIFileError.invalidNote }
    }

    private static func decodeTrack(_ bytes: [UInt8]) throws -> (
        name: String?,
        lengthTicks: Int64,
        notes: [(tick: Int64, pitch: Int, velocity: Int, channel: Int, duration: Int64)]
    ) {
        var cursor = 0
        var tick: Int64 = 0
        var runningStatus: UInt8?
        var name: String?
        var active: [Int: [(tick: Int64, velocity: Int)]] = [:]
        var notes: [(Int64, Int, Int, Int, Int64)] = []

        while cursor < bytes.count {
            tick += Int64(try readVariableLength(bytes, cursor: &cursor))
            guard cursor < bytes.count else { throw StandardMIDIFileError.malformedTrack }
            var status = bytes[cursor]
            if status & 0x80 != 0 {
                cursor += 1
                if status < 0xf0 { runningStatus = status }
            } else if let runningStatus {
                status = runningStatus
            } else {
                throw StandardMIDIFileError.malformedTrack
            }

            if status == 0xff {
                runningStatus = nil
                guard cursor < bytes.count else { throw StandardMIDIFileError.malformedTrack }
                let type = bytes[cursor]
                cursor += 1
                let length = try readVariableLength(bytes, cursor: &cursor)
                guard cursor + length <= bytes.count else { throw StandardMIDIFileError.malformedTrack }
                if type == 0x03, name == nil { name = String(bytes: bytes[cursor ..< cursor + length], encoding: .utf8) }
                cursor += length
                if type == 0x2f { break }
                continue
            }
            if status == 0xf0 || status == 0xf7 {
                runningStatus = nil
                let length = try readVariableLength(bytes, cursor: &cursor)
                guard cursor + length <= bytes.count else { throw StandardMIDIFileError.malformedTrack }
                cursor += length
                continue
            }

            let kind = status & 0xf0
            let channel = Int(status & 0x0f) + 1
            let count = (kind == 0xc0 || kind == 0xd0) ? 1 : 2
            guard cursor + count <= bytes.count else { throw StandardMIDIFileError.malformedTrack }
            let first = Int(bytes[cursor])
            let second = count == 2 ? Int(bytes[cursor + 1]) : 0
            cursor += count
            guard kind == 0x80 || kind == 0x90 else { continue }
            let key = (channel << 8) | first
            if kind == 0x90, second > 0 {
                active[key, default: []].append((tick, second))
            } else if var starts = active[key], !starts.isEmpty {
                let start = starts.removeFirst()
                active[key] = starts
                guard tick > start.tick else { throw StandardMIDIFileError.invalidNote }
                notes.append((start.tick, first, start.velocity, channel, tick - start.tick))
            }
        }
        guard active.values.allSatisfy(\.isEmpty) else { throw StandardMIDIFileError.malformedTrack }
        return (name, tick, notes)
    }

    private static func variableLength(_ value: Int) -> [UInt8] {
        precondition(value >= 0 && value <= 0x0fffffff)
        var value = value
        var buffer = [UInt8(value & 0x7f)]
        value >>= 7
        while value > 0 {
            buffer.append(UInt8(value & 0x7f) | 0x80)
            value >>= 7
        }
        return buffer.reversed()
    }

    private static func readVariableLength(_ bytes: [UInt8], cursor: inout Int) throws -> Int {
        var value = 0
        for _ in 0 ..< 4 {
            guard cursor < bytes.count else { throw StandardMIDIFileError.malformedTrack }
            let byte = bytes[cursor]
            cursor += 1
            value = (value << 7) | Int(byte & 0x7f)
            if byte & 0x80 == 0 { return value }
        }
        throw StandardMIDIFileError.malformedTrack
    }

    private static func bigEndian(_ value: UInt16) -> [UInt8] {
        [UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16) |
            (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }
}
