import CoreMIDI

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
