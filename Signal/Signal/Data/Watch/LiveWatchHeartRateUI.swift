import Foundation

struct LiveWatchHeartRateUIState: Equatable, Sendable {
    let showsHeartRateSlot: Bool
    let bpm: Int?
    let isStale: Bool
    let statusChipTitle: String?
}

enum LiveWatchHeartRateUIStateBuilder {
    static func make(
        isLiveHeartRateRequested: Bool,
        source: LiveHeartRateSource,
        latestHeartRateBPM: Int?,
        lastHeartRateAt: Date?,
        accessStatusMessage: String? = nil,
        now: Date
    ) -> LiveWatchHeartRateUIState {
        guard isLiveHeartRateRequested else {
            return LiveWatchHeartRateUIState(
                showsHeartRateSlot: false,
                bpm: nil,
                isStale: false,
                statusChipTitle: nil
            )
        }

        if let accessStatusMessage, latestHeartRateBPM == nil, lastHeartRateAt == nil {
            return LiveWatchHeartRateUIState(
                showsHeartRateSlot: true,
                bpm: nil,
                isStale: false,
                statusChipTitle: accessStatusMessage
            )
        }

        let fresh = LiveHRCueEvaluator.isHeartRateFresh(
            bpm: latestHeartRateBPM,
            sampledAt: lastHeartRateAt,
            now: now
        )
        let hadSample = lastHeartRateAt != nil || latestHeartRateBPM != nil
        let isStale = hadSample && !fresh

        let statusChipTitle: String?
        if fresh {
            statusChipTitle = nil
        } else if isStale {
            statusChipTitle = staleChipTitle(for: source)
        } else {
            statusChipTitle = waitingChipTitle(for: source)
        }

        return LiveWatchHeartRateUIState(
            showsHeartRateSlot: true,
            bpm: latestHeartRateBPM,
            isStale: isStale,
            statusChipTitle: statusChipTitle
        )
    }

    private static func waitingChipTitle(for source: LiveHeartRateSource) -> String {
        switch source {
        case .watch: "Waiting for watch HR"
        case .phoneHealthKit: "Waiting for heart rate"
        }
    }

    private static func staleChipTitle(for source: LiveHeartRateSource) -> String {
        switch source {
        case .watch: "Watch HR signal lost"
        case .phoneHealthKit: "HR signal lost"
        }
    }
}
