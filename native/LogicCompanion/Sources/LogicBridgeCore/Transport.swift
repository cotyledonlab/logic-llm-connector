import Foundation

public protocol TransportControlling: Sendable {
    func observe(operationID: String) -> TransportStateResult
    func setPlaying(
        _ playing: Bool,
        operationID: String,
        timeoutMilliseconds: Int
    ) -> TransportOperationResult
    func movePlayhead(
        _ direction: TransportMoveDirection,
        steps: Int,
        operationID: String,
        timeoutMilliseconds: Int
    ) -> TransportLocationOperationResult
}

public struct MackieTransportController: TransportControlling, Sendable {
    private let midi: any TransportMIDISending
    private let feedback: any MackieControlFeedbackObserving
    private let now: @Sendable () -> Date
    private let wait: @Sendable (TimeInterval) -> Void

    public init(
        midi: any TransportMIDISending,
        feedback: any MackieControlFeedbackObserving,
        now: @escaping @Sendable () -> Date = Date.init,
        wait: @escaping @Sendable (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
    ) {
        self.midi = midi
        self.feedback = feedback
        self.now = now
        self.wait = wait
    }

    public func observe(operationID: String) -> TransportStateResult {
        let startedAt = now()
        let snapshot = feedback.feedbackSnapshot
        let evidence = evidence(for: snapshot)
        let hasState = snapshot.transportState.playing != .unknown
            || snapshot.transportState.cycle != .unknown
            || snapshot.transportState.recordReady != .unknown
        return TransportStateResult(
            protocolVersion: bridgeProtocolVersion,
            operationID: operationID,
            status: hasState ? .succeeded : .partial,
            reliability: hasState ? .verifiedDeterministic : .bestEffort,
            startedAt: startedAt,
            finishedAt: now(),
            data: snapshot.transportState,
            evidence: evidence
        )
    }

    public func setPlaying(
        _ playing: Bool,
        operationID: String,
        timeoutMilliseconds: Int
    ) -> TransportOperationResult {
        let startedAt = now()
        let requested: TransportPlayingState = playing ? .playing : .stopped
        let initial = feedback.feedbackSnapshot
        if initial.transportState.playing == requested {
            return result(
                operationID: operationID,
                requested: requested,
                dispatched: false,
                status: .succeeded,
                reliability: .verifiedDeterministic,
                startedAt: startedAt,
                snapshot: initial
            )
        }

        let endpoints = midi.snapshot
        guard endpoints.sourceAvailable else {
            return result(
                operationID: operationID,
                requested: requested,
                dispatched: false,
                status: .failed,
                reliability: .unsupported,
                startedAt: startedAt,
                snapshot: initial,
                extraEvidence: [Evidence(
                    source: "CoreMIDI virtual source",
                    observedAt: now(),
                    value: .bool(false)
                )]
            )
        }

        do {
            try press(playing ? .play : .stop)
        } catch {
            return result(
                operationID: operationID,
                requested: requested,
                dispatched: false,
                status: .failed,
                reliability: .bestEffort,
                startedAt: startedAt,
                snapshot: feedback.feedbackSnapshot,
                extraEvidence: [Evidence(
                    source: "CoreMIDI dispatch",
                    observedAt: now(),
                    value: .string(String(describing: error))
                )]
            )
        }

        let deadline = startedAt.addingTimeInterval(
            TimeInterval(timeoutMilliseconds) / 1_000
        )
        var latest = feedback.feedbackSnapshot
        while now() < deadline {
            latest = feedback.feedbackSnapshot
            if latest.transportSequence > initial.transportSequence,
               latest.transportState.playing == requested {
                return result(
                    operationID: operationID,
                    requested: requested,
                    dispatched: true,
                    status: .succeeded,
                    reliability: .verifiedDeterministic,
                    startedAt: startedAt,
                    snapshot: latest
                )
            }
            wait(0.01)
        }

        return result(
            operationID: operationID,
            requested: requested,
            dispatched: true,
            status: .timedOut,
            reliability: .bestEffort,
            startedAt: startedAt,
            snapshot: latest,
            extraEvidence: [Evidence(
                source: "Mackie Control feedback deadline",
                observedAt: now(),
                value: .number(Double(timeoutMilliseconds))
            )]
        )
    }

    public func movePlayhead(
        _ direction: TransportMoveDirection,
        steps: Int,
        operationID: String,
        timeoutMilliseconds: Int
    ) -> TransportLocationOperationResult {
        let startedAt = now()
        let initial = feedback.feedbackSnapshot
        guard let initialDisplay = initial.positionDisplay else {
            return locationResult(
                operationID: operationID,
                direction: direction,
                steps: steps,
                dispatched: false,
                status: .failed,
                reliability: .unsupported,
                startedAt: startedAt,
                initial: initial,
                latest: initial
            )
        }

        guard midi.snapshot.sourceAvailable else {
            return locationResult(
                operationID: operationID,
                direction: direction,
                steps: steps,
                dispatched: false,
                status: .failed,
                reliability: .unsupported,
                startedAt: startedAt,
                initial: initial,
                latest: initial
            )
        }

        let deadline = startedAt.addingTimeInterval(
            TimeInterval(timeoutMilliseconds) / 1_000
        )
        let firstRefreshDeadline = startedAt.addingTimeInterval(
            TimeInterval(timeoutMilliseconds) / 2_000
        )
        var firstRefreshSequence: UInt64?
        do {
            let value: UInt32 = direction == .forward ? 0x01 : 0x41
            for _ in 0..<steps {
                try midi.send(MIDIMessage(timestamp: 0, words: [0x20B0_3C00 | value]))
            }
            try press(.smpteBeats)
            while now() < firstRefreshDeadline {
                let refreshed = feedback.feedbackSnapshot
                if refreshed.positionSequence > initial.positionSequence {
                    firstRefreshSequence = refreshed.positionSequence
                    break
                }
                wait(0.01)
            }
            try press(.smpteBeats)
        } catch {
            return locationResult(
                operationID: operationID,
                direction: direction,
                steps: steps,
                dispatched: false,
                status: .failed,
                reliability: .bestEffort,
                startedAt: startedAt,
                initial: initial,
                latest: feedback.feedbackSnapshot,
                extraEvidence: [Evidence(
                    source: "CoreMIDI dispatch",
                    observedAt: now(),
                    value: .string(String(describing: error))
                )]
            )
        }

        var latest = feedback.feedbackSnapshot
        while now() < deadline {
            latest = feedback.feedbackSnapshot
            if let firstRefreshSequence,
               latest.positionSequence > firstRefreshSequence,
               let latestDisplay = latest.positionDisplay,
               moved(from: initialDisplay, to: latestDisplay, direction: direction) {
                return locationResult(
                    operationID: operationID,
                    direction: direction,
                    steps: steps,
                    dispatched: true,
                    status: .succeeded,
                    reliability: .verifiedDeterministic,
                    startedAt: startedAt,
                    initial: initial,
                    latest: latest
                )
            }
            wait(0.01)
        }

        return locationResult(
            operationID: operationID,
            direction: direction,
            steps: steps,
            dispatched: true,
            status: .timedOut,
            reliability: .bestEffort,
            startedAt: startedAt,
            initial: initial,
            latest: latest,
            extraEvidence: [Evidence(
                source: "Mackie Control position feedback deadline",
                observedAt: now(),
                value: .number(Double(timeoutMilliseconds))
            )]
        )
    }

    private func press(_ note: MackieTransportNote) throws {
        let timestamp: UInt64 = 0
        try midi.send(MIDIMessage(
            timestamp: timestamp,
            words: [0x2090_0000 | UInt32(note.rawValue) << 8 | 0x7F]
        ))
        try midi.send(MIDIMessage(
            timestamp: timestamp,
            words: [0x2090_0000 | UInt32(note.rawValue) << 8]
        ))
    }

    private func result(
        operationID: String,
        requested: TransportPlayingState,
        dispatched: Bool,
        status: OperationStatus,
        reliability: Reliability,
        startedAt: Date,
        snapshot: MackieControlFeedbackSnapshot,
        extraEvidence: [Evidence] = []
    ) -> TransportOperationResult {
        TransportOperationResult(
            protocolVersion: bridgeProtocolVersion,
            operationID: operationID,
            status: status,
            reliability: reliability,
            startedAt: startedAt,
            finishedAt: now(),
            data: TransportOperationData(
                requestedState: requested,
                commandDispatched: dispatched,
                state: snapshot.transportState
            ),
            evidence: evidence(for: snapshot) + extraEvidence
        )
    }

    private func evidence(for snapshot: MackieControlFeedbackSnapshot) -> [Evidence] {
        guard let observedAt = snapshot.transportState.observedAt else { return [] }
        return [Evidence(
            source: "Mackie Control feedback",
            observedAt: observedAt,
            value: .object([
                "sequence": .number(Double(snapshot.transportSequence)),
                "playing": .string(snapshot.transportState.playing.rawValue),
                "cycle": .string(snapshot.transportState.cycle.rawValue),
                "recordReady": .string(snapshot.transportState.recordReady.rawValue),
            ])
        )]
    }

    private func moved(
        from initial: String,
        to latest: String,
        direction: TransportMoveDirection
    ) -> Bool {
        switch direction {
        case .backward: latest < initial
        case .forward: latest > initial
        }
    }

    private func locationResult(
        operationID: String,
        direction: TransportMoveDirection,
        steps: Int,
        dispatched: Bool,
        status: OperationStatus,
        reliability: Reliability,
        startedAt: Date,
        initial: MackieControlFeedbackSnapshot,
        latest: MackieControlFeedbackSnapshot,
        extraEvidence: [Evidence] = []
    ) -> TransportLocationOperationResult {
        let initialPosition = TransportPositionData(
            display: initial.positionDisplay,
            observedAt: initial.positionObservedAt
        )
        let position = TransportPositionData(
            display: latest.positionDisplay,
            observedAt: latest.positionObservedAt
        )
        var evidence = extraEvidence
        if let observedAt = latest.positionObservedAt,
           let display = latest.positionDisplay {
            evidence.insert(Evidence(
                source: "Mackie Control position feedback",
                observedAt: observedAt,
                value: .object([
                    "sequence": .number(Double(latest.positionSequence)),
                    "display": .string(display),
                ])
            ), at: 0)
        }
        return TransportLocationOperationResult(
            protocolVersion: bridgeProtocolVersion,
            operationID: operationID,
            status: status,
            reliability: reliability,
            startedAt: startedAt,
            finishedAt: now(),
            data: TransportLocationOperationData(
                requestedDirection: direction,
                steps: steps,
                commandDispatched: dispatched,
                initialPosition: initialPosition,
                position: position
            ),
            evidence: evidence
        )
    }
}
