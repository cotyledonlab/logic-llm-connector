import Foundation

public struct ControlSurfaceAssignment: Sendable, Equatable {
    public let model: String
    public let inputPort: String?
    public let outputPort: String?

    public init(model: String, inputPort: String?, outputPort: String?) {
        self.model = model
        self.inputPort = inputPort
        self.outputPort = outputPort
    }
}

public enum MackieControlConfigurationState: String, Sendable, Equatable {
    case missing
    case configured
    case conflicting
}

public struct MackieControlConfiguration: Sendable, Equatable {
    public let state: MackieControlConfigurationState
    public let assignments: [ControlSurfaceAssignment]

    public init(
        state: MackieControlConfigurationState,
        assignments: [ControlSurfaceAssignment]
    ) {
        self.state = state
        self.assignments = assignments
    }
}

public enum MackieControlObservationUnavailableReason: String, Sendable, Equatable {
    case accessibilityNotTrusted = "accessibility_not_trusted"
    case logicNotRunning = "logic_not_running"
    case setupWindowClosed = "setup_window_closed"
    case unreadableSetupWindow = "unreadable_setup_window"
}

public enum MackieControlObservation: Sendable, Equatable {
    case observed(MackieControlConfiguration)
    case unavailable(MackieControlObservationUnavailableReason)
}

public enum MackieControlConfigurationClassifier {
    public static let expectedModel = "Mackie Control"
    public static let expectedInputPort = VirtualMIDIEndpointIdentity.source.name
    public static let expectedOutputPort = VirtualMIDIEndpointIdentity.destination.name

    public static func classify(
        _ assignments: [ControlSurfaceAssignment]
    ) -> MackieControlConfiguration {
        let relevant = assignments.filter {
            $0.inputPort == expectedInputPort || $0.outputPort == expectedOutputPort
        }
        guard !relevant.isEmpty else {
            return MackieControlConfiguration(state: .missing, assignments: [])
        }

        let expected = relevant.filter {
            $0.model == expectedModel
                && $0.inputPort == expectedInputPort
                && $0.outputPort == expectedOutputPort
        }
        let state: MackieControlConfigurationState =
            relevant.count == 1 && expected.count == 1 ? .configured : .conflicting
        return MackieControlConfiguration(state: state, assignments: relevant)
    }
}

public protocol MackieControlConfigurationObserving: Sendable {
    var mackieControlObservation: MackieControlObservation { get }
}
