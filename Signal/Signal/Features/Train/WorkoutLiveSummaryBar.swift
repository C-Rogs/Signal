import SwiftUI

struct WorkoutLiveSummaryBar: View {
    let summary: WorkoutLiveSummary
    let formatter: DisplayUnitFormatter

    var body: some View {
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
            if let heartRateBPM = summary.heartRateBPM {
                statDivider
                statColumn(
                    title: "HR",
                    value: "\(heartRateBPM)",
                    emphasize: true
                )
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summaryAccessibilityLabel)
    }

    private var formattedVolume: String {
        if summary.volumeKg <= 0 {
            return "—"
        }
        return formatter.formatMassKg(summary.volumeKg)
    }

    private var summaryAccessibilityLabel: String {
        var parts = [
            "Duration \(WorkoutLiveSummary.formatDuration(seconds: summary.durationSeconds))",
            "volume \(formattedVolume)",
            "\(summary.completedSetCount) sets completed",
        ]
        if let heartRateBPM = summary.heartRateBPM {
            parts.append("heart rate \(heartRateBPM)")
        }
        return parts.joined(separator: ", ")
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color("TextSecondary").opacity(0.25))
            .frame(width: 1, height: 36)
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
