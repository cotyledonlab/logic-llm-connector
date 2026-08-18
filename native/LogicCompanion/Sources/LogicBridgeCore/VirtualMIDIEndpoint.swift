import CoreMIDI
import Foundation

public struct VirtualMIDIEndpointDescriptor: Sendable, Equatable {
    public let name: String
    public let uniqueID: MIDIUniqueID

    public init(name: String, uniqueID: MIDIUniqueID) {
        self.name = name
        self.uniqueID = uniqueID
    }
}

public enum VirtualMIDIEndpointIdentity {
    public static let clientName = "Logic LLM Connector"
    public static let manufacturer = "Cotyledon Lab"
    public static let model = "Logic LLM Connector Control"
    public static let protocolID: MIDIProtocolID = ._1_0
    public static let source = VirtualMIDIEndpointDescriptor(
        name: "Logic LLM Connector Out",
        uniqueID: 0x4C4C_4D01
    )
    public static let destination = VirtualMIDIEndpointDescriptor(
        name: "Logic LLM Connector In",
        uniqueID: 0x4C4C_4D02
    )
}

public struct VirtualMIDIEndpointSnapshot: Sendable, Equatable {
    public let sourceAvailable: Bool
    public let destinationAvailable: Bool
    public let protocolID: MIDIProtocolID

    public init(
        sourceAvailable: Bool,
        destinationAvailable: Bool,
        protocolID: MIDIProtocolID
    ) {
        self.sourceAvailable = sourceAvailable
        self.destinationAvailable = destinationAvailable
        self.protocolID = protocolID
    }
}

public protocol VirtualMIDIEndpointObserving: Sendable {
    var snapshot: VirtualMIDIEndpointSnapshot { get }
}

public protocol TransportMIDISending: VirtualMIDIEndpointObserving {
    func send(_ message: MIDIMessage) throws
}

public struct MIDIMessage: Sendable, Equatable {
    public let timestamp: MIDITimeStamp
    public let words: [UInt32]

    public init(timestamp: MIDITimeStamp, words: [UInt32]) {
        self.timestamp = timestamp
        self.words = words
    }
}

public struct VirtualMIDIEndpointError: Error, Sendable, Equatable, CustomStringConvertible {
    public let operation: String
    public let status: OSStatus

    public init(operation: String, status: OSStatus) {
        self.operation = operation
        self.status = status
    }

    public var description: String {
        "CoreMIDI \(operation) failed with OSStatus \(status)"
    }
}

public final class VirtualMIDIEndpointOwner: TransportMIDISending, @unchecked Sendable {
    private let lock = NSLock()
    private let receiveQueue: DispatchQueue
    private let onReceive: @Sendable ([MIDIMessage]) -> Void
    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var destination = MIDIEndpointRef()

    public init(
        receiveQueue: DispatchQueue = DispatchQueue(
            label: "dev.cotyledonlab.logic-llm-connector.midi-receive",
            qos: .userInitiated
        ),
        onReceive: @escaping @Sendable ([MIDIMessage]) -> Void = { _ in }
    ) throws {
        self.receiveQueue = receiveQueue
        self.onReceive = onReceive
        try check(
            MIDIClientCreateWithBlock(
                VirtualMIDIEndpointIdentity.clientName as CFString,
                &client,
                { _ in }
            ),
            operation: "client creation"
        )

        do {
            try createEndpoints()
        } catch {
            MIDIClientDispose(client)
            client = MIDIClientRef()
            throw error
        }
    }

    deinit {
        if client != MIDIClientRef() {
            MIDIClientDispose(client)
        }
    }

    public var snapshot: VirtualMIDIEndpointSnapshot {
        lock.withLock { snapshotWithoutLocking() }
    }

    @discardableResult
    public func ensureAvailable() throws -> VirtualMIDIEndpointSnapshot {
        try lock.withLock {
            if !endpointIsAvailable(
                source,
                uniqueID: VirtualMIDIEndpointIdentity.source.uniqueID
            ) {
                source = MIDIEndpointRef()
                try createSource()
            }
            if !endpointIsAvailable(
                destination,
                uniqueID: VirtualMIDIEndpointIdentity.destination.uniqueID
            ) {
                destination = MIDIEndpointRef()
                try createDestination()
            }
            return snapshotWithoutLocking()
        }
    }

    private func snapshotWithoutLocking() -> VirtualMIDIEndpointSnapshot {
        VirtualMIDIEndpointSnapshot(
            sourceAvailable: endpointIsAvailable(
                source,
                uniqueID: VirtualMIDIEndpointIdentity.source.uniqueID
            ),
            destinationAvailable: endpointIsAvailable(
                destination,
                uniqueID: VirtualMIDIEndpointIdentity.destination.uniqueID
            ),
            protocolID: VirtualMIDIEndpointIdentity.protocolID
        )
    }

    public func send(_ message: MIDIMessage) throws {
        guard (1...64).contains(message.words.count) else {
            throw VirtualMIDIEndpointError(
                operation: "event list construction",
                status: OSStatus(paramErr)
            )
        }

        try lock.withLock {
            var eventList = MIDIEventList()
            let status = withUnsafeMutablePointer(to: &eventList) { eventListPointer in
                let packet = MIDIEventListInit(
                    eventListPointer,
                    VirtualMIDIEndpointIdentity.protocolID
                )
                message.words.withUnsafeBufferPointer { words in
                    _ = MIDIEventListAdd(
                        eventListPointer,
                        MemoryLayout<MIDIEventList>.size,
                        packet,
                        message.timestamp,
                        words.count,
                        words.baseAddress!
                    )
                }
                return MIDIReceivedEventList(source, eventListPointer)
            }
            try check(status, operation: "source send")
        }
    }

    private func createEndpoints() throws {
        try createSource()

        do {
            try createDestination()
        } catch {
            MIDIEndpointDispose(source)
            source = MIDIEndpointRef()
            throw error
        }
    }

    private func createSource() throws {
        try check(
            MIDISourceCreateWithProtocol(
                client,
                VirtualMIDIEndpointIdentity.source.name as CFString,
                VirtualMIDIEndpointIdentity.protocolID,
                &source
            ),
            operation: "source creation"
        )
        do {
            try applyIdentity(VirtualMIDIEndpointIdentity.source, to: source)
        } catch {
            MIDIEndpointDispose(source)
            source = MIDIEndpointRef()
            throw error
        }
    }

    private func createDestination() throws {
        do {
            try check(
                MIDIDestinationCreateWithProtocol(
                    client,
                    VirtualMIDIEndpointIdentity.destination.name as CFString,
                    VirtualMIDIEndpointIdentity.protocolID,
                    &destination,
                    { [receiveQueue, onReceive] eventList, _ in
                        let messages = Self.copyMessages(from: eventList)
                        receiveQueue.async {
                            onReceive(messages)
                        }
                    }
                ),
                operation: "destination creation"
            )
            try applyIdentity(VirtualMIDIEndpointIdentity.destination, to: destination)
        } catch {
            if destination != MIDIEndpointRef() {
                MIDIEndpointDispose(destination)
                destination = MIDIEndpointRef()
            }
            throw error
        }
    }

    private func applyIdentity(
        _ identity: VirtualMIDIEndpointDescriptor,
        to endpoint: MIDIEndpointRef
    ) throws {
        try check(
            MIDIObjectSetIntegerProperty(endpoint, kMIDIPropertyUniqueID, identity.uniqueID),
            operation: "unique ID assignment"
        )
        try check(
            MIDIObjectSetStringProperty(
                endpoint,
                kMIDIPropertyManufacturer,
                VirtualMIDIEndpointIdentity.manufacturer as CFString
            ),
            operation: "manufacturer assignment"
        )
        try check(
            MIDIObjectSetStringProperty(
                endpoint,
                kMIDIPropertyModel,
                VirtualMIDIEndpointIdentity.model as CFString
            ),
            operation: "model assignment"
        )
    }

    private func endpointIsAvailable(
        _ endpoint: MIDIEndpointRef,
        uniqueID: MIDIUniqueID
    ) -> Bool {
        guard endpoint != MIDIEndpointRef() else { return false }
        var observedID = MIDIUniqueID()
        return MIDIObjectGetIntegerProperty(
            endpoint,
            kMIDIPropertyUniqueID,
            &observedID
        ) == noErr && observedID == uniqueID
    }

    private static func copyMessages(
        from eventList: UnsafePointer<MIDIEventList>
    ) -> [MIDIMessage] {
        var messages: [MIDIMessage] = []
        var packet = withUnsafePointer(to: eventList.pointee.packet) {
            UnsafeRawPointer($0).assumingMemoryBound(to: MIDIEventPacket.self)
        }
        for _ in 0..<eventList.pointee.numPackets {
            let words = withUnsafePointer(to: packet.pointee.words) {
                Array(UnsafeBufferPointer(
                    start: UnsafeRawPointer($0).assumingMemoryBound(to: UInt32.self),
                    count: Int(packet.pointee.wordCount)
                ))
            }
            messages.append(
                MIDIMessage(
                    timestamp: packet.pointee.timeStamp,
                    words: words
                )
            )
            packet = UnsafePointer(MIDIEventPacketNext(packet))
        }
        return messages
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw VirtualMIDIEndpointError(operation: operation, status: status)
        }
    }
}
