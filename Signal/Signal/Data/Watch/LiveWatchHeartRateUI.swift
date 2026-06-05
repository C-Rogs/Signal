import Foundation

struct LiveWatchHeartRateUIState: Equatable, Sendable {
    let showsHeartRateSlot: Bool
    let bpm: Int?
    let isStale: Bool
    let statusChipTitle: String?
}

enum LiveWatchHeartRateUIStateBuilder {
    static func make(
        isWatchWorkoutRequested: Bool,
        latestHeartRateBPM: Int?,
        lastHeartRateAt: Date?,
        now: Date
    ) -> LiveWatchHeartRateUIState {
        guard isWatchWorkoutRequested else {
            return LiveWatchHeartRateUIState(
                showsHeartRateSlot: false,
                bpm: nil,
                isStale: false,
                statusChipTitle: nil
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
            statusChipTitle = "Watch HR signal lost"
        } else {
            statusChipTitle = "Waiting for watch HR"
        }

        return LiveWatchHeartRateUIState(
            showsHeartRateSlot: true,
            bpm: latestHeartRateBPM,
            isStale: isStale,
            statusChipTitle: statusChipTitle
        )
    }
}
