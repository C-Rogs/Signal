import Foundation

enum SetHRAttributionMath: Sendable {
    static let minimumSampleCount = 3

    static func buildDraftsForSession(
        payload: SetHRAttributionSessionPayload,
        samples: [HeartRateSamplePoint]
    ) -> [SetHeartRateDataDraft] {
        var drafts: [SetHeartRateDataDraft] = []
        for exerciseSets in payload.setsByExercise {
            drafts.append(
                contentsOf: computeDrafts(
                    sessionID: payload.sessionID,
                    sets: exerciseSets,
                    samples: samples
                )
            )
        }
        return drafts
    }

    static func computeDrafts(
        sessionID: UUID,
        sets: [SetHRAttributionSetInput],
        samples: [HeartRateSamplePoint]
    ) -> [SetHeartRateDataDraft] {
        let qualifying = sets
            .filter { !$0.isWarmup }
            .compactMap { set -> (SetHRAttributionSetInput, Date, Date)? in
                guard let start = set.startedAt, let end = set.completedAt else { return nil }
                return (set, start, end)
            }
            .sorted { $0.0.setIndex < $1.0.setIndex }

        var drafts: [SetHeartRateDataDraft] = []
        drafts.reserveCapacity(qualifying.count * 2)

        for (set, windowStart, windowEnd) in qualifying {
            if let draft = draft(
                sessionID: sessionID,
                setEntryID: set.entryID,
                windowStart: windowStart,
                windowEnd: windowEnd,
                samples: samples,
                isRestInterval: false
            ) {
                drafts.append(draft)
            }
        }

        for index in qualifying.indices.dropLast() {
            let (_, _, restStart) = qualifying[index]
            let (nextSet, restEnd, _) = qualifying[index + 1]
            guard restEnd > restStart else { continue }
            if let draft = draft(
                sessionID: sessionID,
                setEntryID: nextSet.entryID,
                windowStart: restStart,
                windowEnd: restEnd,
                samples: samples,
                isRestInterval: true
            ) {
                drafts.append(draft)
            }
        }

        return drafts
    }

    private static func draft(
        sessionID: UUID,
        setEntryID: UUID,
        windowStart: Date,
        windowEnd: Date,
        samples: [HeartRateSamplePoint],
        isRestInterval: Bool
    ) -> SetHeartRateDataDraft? {
        let bpmValues = samples.compactMap { sample -> Double? in
            guard sample.timestamp >= windowStart, sample.timestamp <= windowEnd else { return nil }
            return sample.bpm
        }
        guard bpmValues.count >= minimumSampleCount else { return nil }
        let avg = bpmValues.reduce(0, +) / Double(bpmValues.count)
        return SetHeartRateDataDraft(
            setEntryID: setEntryID,
            sessionID: sessionID,
            avgBPM: avg,
            maxBPM: bpmValues.max() ?? avg,
            minBPM: bpmValues.min() ?? avg,
            sampleCount: bpmValues.count,
            windowStart: windowStart,
            windowEnd: windowEnd,
            isRestInterval: isRestInterval
        )
    }
}
