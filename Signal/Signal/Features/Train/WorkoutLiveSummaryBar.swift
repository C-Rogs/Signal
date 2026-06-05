import SwiftUI

struct WorkoutLiveSummaryBar: View {
    let summary: WorkoutLiveSummary
    let formatter: DisplayUnitFormatter
    var recoveryChipTitle: String?
    var deloadChipTitle: String?
    var heartRateUI: LiveWatchHeartRateUIState = LiveWatchHeartRateUIState(
        showsHeartRateSlot: false,
        bpm: nil,
        isStale: false,
        statusChipTitle: nil
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let recoveryChipTitle {
                Text(recoveryChipTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color("Warning"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color("Warning").opacity(0.15))
                    .clipShape(Capsule())
                    .accessibilityIdentifier("lowRecoveryChip")
            }
            if let deloadChipTitle {
                Text(deloadChipTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color("Warning"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color("Warning").opacity(0.15))
                    .clipShape(Capsule())
                    .accessibilityIdentifier("deloadSuggestedChip")
            }
            if let statusChipTitle = heartRateUI.statusChipTitle {
                Text(statusChipTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color("TextSecondary"))
                    .accessibilityIdentifier("watchHeartRateStatusChip")
            }
            statsRow
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summaryAccessibilityLabel)
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statColumn(
                title: "Duration",
                value: WorkoutLiveSummary.formatDuration(seconds: summary.durationSeconds),
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
                value: "\(summary.completedSetCount)",
                emphasize: false
            )
            if heartRateUI.showsHeartRateSlot {
                statDivider
                liveHeartRateColumn
            }
        }
    }

    private var formattedVolume: String {
        if summary.volumeKg <= 0 {
            return "—"
        }
        return formatter.formatMassKg(summary.volumeKg)
    }

    private var summaryAccessibilityLabel: String {
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
            "Duration \(WorkoutLiveSummary.formatDuration(seconds: summary.durationSeconds))",
            "volume \(formattedVolume)",
            "\(summary.completedSetCount) sets completed",
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
            .fill(Color("TextSecondary").opacity(0.25))
            .frame(width: 1, height: 36)
    }

    private var liveHeartRateColumn: some View {
        ZStack {
            LiveHeartRateDecor()
                .frame(height: 40)
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    Image(systemName: LiveHeartRateIcon.liveSymbol)
                        .font(.caption2)
                        .symbolRenderingMode(.hierarchical)
                    Text("BPM")
                        .font(.caption)
                }
                .foregroundStyle(Color("Primary"))
                if let bpm = heartRateUI.bpm {
                    Text("\(bpm)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
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
                        .font(.subheadline.weight(.semibold).monospacedDigit())
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
                .font(.caption)
                .foregroundStyle(Color("TextSecondary"))
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(emphasize ? Color("Primary") : Color("TextPrimary"))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
