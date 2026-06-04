import Foundation

enum LiveWorkoutAutoregulation {
    /// Matches foamy-pixel example ("HR still 150, rest longer") and SetHeartRateDisplay warning band.
    static let elevatedHeartRateThresholdBPM = 150
    static let heartRateFreshnessSeconds: TimeInterval = 45
    static let restExtensionSeconds = 30
    static let maxExtensionsPerRest = 2
    static let minIntervalBetweenExtensions: TimeInterval = 20
    static let skipExtensionWhenRemainingUnder: TimeInterval = 8
}

struct DynamicRestState: Sendable, Equatable {
    var trackedExerciseID: String?
    var extensionCount: Int = 0
    var lastExtensionAt: Date?
}

enum LiveHRCueEvaluator {
    static func isHeartRateFresh(bpm: Int?, sampledAt: Date?, now: Date) -> Bool {
        guard let bpm, bpm > 0, let sampledAt else { return false }
        return now.timeIntervalSince(sampledAt) <= LiveWorkoutAutoregulation.heartRateFreshnessSeconds
    }

    static func isElevated(bpm: Int) -> Bool {
        bpm >= LiveWorkoutAutoregulation.elevatedHeartRateThresholdBPM
    }

    static func restNudgeAfterSet(bpm: Int?, sampledAt: Date?, now: Date) -> String? {
        guard isHeartRateFresh(bpm: bpm, sampledAt: sampledAt, now: now),
              let bpm,
              isElevated(bpm: bpm)
        else { return nil }
        return "Heart rate still \(bpm). Take the full rest."
    }

    static func composedSetCue(tierMessage: String?, heartRateBPM: Int?, heartRateSampledAt: Date?, now: Date) -> String? {
        LiveSetCueComposer.compose(
            tierMessage: tierMessage,
            loadNudge: nil,
            heartRateBPM: heartRateBPM,
            heartRateSampledAt: heartRateSampledAt,
            now: now
        )
    }
}

/// Composed set banner (max 3 lines), in display order:
/// 1. Tier cue (CueEngine performance)
/// 2. Live HR rest nudge
/// 3. Load / readiness prescription nudge
enum LiveSetCueComposer {
    static func compose(
        tierMessage: String?,
        loadNudge: String?,
        heartRateBPM: Int?,
        heartRateSampledAt: Date?,
        now: Date
    ) -> String? {
        let hrNudge = LiveHRCueEvaluator.restNudgeAfterSet(
            bpm: heartRateBPM,
            sampledAt: heartRateSampledAt,
            now: now
        )
        let lines = [tierMessage, hrNudge, loadNudge].compactMap { line -> String? in
            guard let line, !line.isEmpty else { return nil }
            return line
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }
}

enum DynamicRestTimerEvaluator {
    struct Input: Sendable, Equatable {
        let exerciseID: String
        let heartRateBPM: Int?
        let heartRateSampledAt: Date?
        let now: Date
        let restEndsAt: Date
        let state: DynamicRestState
    }

    struct Decision: Sendable, Equatable {
        let newState: DynamicRestState
        let extensionSeconds: Int
        let notice: String
    }

    static func evaluate(_ input: Input) -> Decision? {
        var state = input.state
        if state.trackedExerciseID != input.exerciseID {
            state = DynamicRestState(trackedExerciseID: input.exerciseID)
        }

        let remaining = input.restEndsAt.timeIntervalSince(input.now)
        guard remaining > LiveWorkoutAutoregulation.skipExtensionWhenRemainingUnder else { return nil }
        guard state.extensionCount < LiveWorkoutAutoregulation.maxExtensionsPerRest else { return nil }
        if let last = state.lastExtensionAt,
           input.now.timeIntervalSince(last) < LiveWorkoutAutoregulation.minIntervalBetweenExtensions
        {
            return nil
        }
        guard LiveHRCueEvaluator.isHeartRateFresh(
            bpm: input.heartRateBPM,
            sampledAt: input.heartRateSampledAt,
            now: input.now
        ),
            let bpm = input.heartRateBPM,
            LiveHRCueEvaluator.isElevated(bpm: bpm)
        else { return nil }

        state.extensionCount += 1
        state.lastExtensionAt = input.now
        let seconds = LiveWorkoutAutoregulation.restExtensionSeconds
        let notice = "+\(seconds)s, HR still \(bpm)"
        return Decision(
            newState: state,
            extensionSeconds: seconds,
            notice: notice
        )
    }
}
