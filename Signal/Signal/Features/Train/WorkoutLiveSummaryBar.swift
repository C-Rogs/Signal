import SwiftUI

struct WorkoutLiveSummaryBar: View {
    let sessionStartTime: Date
    let volumeKg: Double
    let completedSetCount: Int
    let formatter: DisplayUnitFormatter
    let watchBridge: LiveWorkoutWatchBridge
    var recoveryChipTitle: String?
    var deloadChipTitle: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date
            let durationSeconds = max(0, Int(now.timeIntervalSince(sessionStartTime)))
            let heartRateUI = watchBridge.heartRateUIState(now: now)

            VStack(alignment: .leading, spacing: 10) {
                if recoveryChipTitle != nil || deloadChipTitle != nil || heartRateUI.statusChipTitle != nil {
                    HStack(spacing: 8) {
                        if let recoveryChipTitle {
                            TrainStatusChip(
                                title: recoveryChipTitle,
                                style: .warning,
                                accessibilityIdentifier: "lowRecoveryChip"
                            )
                        }
                        if let deloadChipTitle {
                            TrainStatusChip(
                                title: deloadChipTitle,
                                style: .warning,
                                accessibilityIdentifier: "deloadSuggestedChip"
                            )
                        }
                    }
                }
                if let statusChipTitle = heartRateUI.statusChipTitle {
                    TrainStatusChip(
                        title: statusChipTitle,
                        style: .secondary,
                        accessibilityIdentifier: "watchHeartRateStatusChip"
                    )
                }
                statsRow(durationSeconds: durationSeconds, heartRateUI: heartRateUI)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                summaryAccessibilityLabel(
                    durationSeconds: durationSeconds,
                    heartRateUI: heartRateUI
                )
            )
        }
    }

    private func statsRow(durationSeconds: Int, heartRateUI: LiveWatchHeartRateUIState) -> some View {
        HStack(spacing: 0) {
            statColumn(
                title: "Duration",
                value: WorkoutLiveSummary.formatDuration(seconds: durationSeconds),
                emphasize: true
            )
            statDivider
            statColumn(
                title: "Volume",
                value: formattedVolume,
                emphasize: false
            )
            statDivider
            statColumn(
                title: "Sets",
                value: "\(completedSetCount)",
                emphasize: false
            )
            if heartRateUI.showsHeartRateSlot {
                statDivider
                liveHeartRateColumn(heartRateUI: heartRateUI)
            }
        }
    }

    private var formattedVolume: String {
        if volumeKg <= 0 {
            return "—"
        }
        return formatter.formatMassKg(volumeKg)
    }

    private func summaryAccessibilityLabel(
        durationSeconds: Int,
        heartRateUI: LiveWatchHeartRateUIState
    ) -> String {
        var parts: [String] = []
        if let recoveryChipTitle {
            parts.append(recoveryChipTitle)
        }
        if let deloadChipTitle {
            parts.append(deloadChipTitle)
        }
        if let statusChipTitle = heartRateUI.statusChipTitle {
            parts.append(statusChipTitle)
        }
        parts.append(contentsOf: [
            "Duration \(WorkoutLiveSummary.formatDuration(seconds: durationSeconds))",
            "volume \(formattedVolume)",
            "\(completedSetCount) sets completed",
        ])
        if let bpm = heartRateUI.bpm {
            let freshness = heartRateUI.isStale ? "stale" : "live"
            parts.append("heart rate \(bpm) \(freshness)")
        } else if heartRateUI.showsHeartRateSlot {
            parts.append("heart rate waiting")
        }
        return parts.joined(separator: ", ")
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color("TextSecondary").opacity(0.2))
            .frame(width: 1, height: 40)
    }

    private func liveHeartRateColumn(heartRateUI: LiveWatchHeartRateUIState) -> some View {
        ZStack {
            LiveHeartRateDecor()
                .frame(height: 40)
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    Image(systemName: LiveHeartRateIcon.liveSymbol)
                        .font(.caption2)
                        .symbolRenderingMode(.hierarchical)
                    Text("BPM")
                        .font(.metadataCaption)
                }
                .foregroundStyle(Color("Primary"))
                if let bpm = heartRateUI.bpm {
                    Text("\(bpm)")
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color("TextPrimary"))
                        .opacity(heartRateUI.isStale ? 0.45 : 1)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                } else {
                    Image(systemName: LiveHeartRateIcon.liveSymbol)
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color("Primary").opacity(0.45))
                        .symbolEffect(.pulse, options: .repeating)
                    Text("—")
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color("TextSecondary"))
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("liveHeartRateColumn")
    }

    private func statColumn(title: String, value: String, emphasize: Bool) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.metadataCaption)
                .foregroundStyle(Color("TextSecondary"))
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(emphasize ? Color("Primary") : Color("TextPrimary"))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
