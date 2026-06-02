import SwiftUI

struct DashboardRecoveryCard: View {
    let indicator: RecoveryIndicator
    let rollingMeans: MetricRollingMeans
    let window: RecoveryWindow

    private var windowMean: WindowMean {
        rollingMeans.mean(for: window)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Symbol.recovery.hierarchicalImage()
                    .font(.title2)
                Text("Recovery")
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextPrimary"))
                Spacer(minLength: 0)
                statusBadge
            }

            Text(DashboardFormatting.recoveryScore(indicator.score))
                .font(.metricValue)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 6) {
                baselineRow(
                    label: "HRV today",
                    today: DashboardFormatting.hrv(indicator.todayHRV),
                    baseline: baselineHRVText
                )
                baselineRow(
                    label: "Resting HR",
                    today: DashboardFormatting.heartRate(indicator.todayRestingHR),
                    baseline: baselineRHRText
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("Surface"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusBadge: some View {
        Text(statusTitle)
            .font(.metadataCaption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(statusColor)
            .background(statusColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var statusTitle: String {
        switch indicator.status {
        case .recovered: "Recovered"
        case .steady: "Steady"
        case .fatigued: "Fatigued"
        case .unknown: "No data"
        }
    }

    private var statusColor: Color {
        switch indicator.status {
        case .recovered: Color("Positive")
        case .steady: Color("Primary")
        case .fatigued: Color("Warning")
        case .unknown: Color("TextSecondary")
        }
    }

    private var baselineHRVText: String {
        guard let mean = windowMean.hrvSDNN else { return "— avg" }
        return "\(Int(mean.rounded())) ms \(window.label) avg"
    }

    private var baselineRHRText: String {
        guard let mean = windowMean.restingHR else { return "— avg" }
        return "\(Int(mean.rounded())) bpm \(window.label) avg"
    }

    private func baselineRow(label: String, today: String, baseline: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.metadataCaption)
                .foregroundStyle(Color("TextSecondary"))
            Spacer(minLength: 8)
            Text(today)
                .font(.metadataCaption)
                .foregroundStyle(Color("TextPrimary"))
            Text(baseline)
                .font(.metadataCaption)
                .foregroundStyle(Color("TextSecondary"))
        }
    }
}
