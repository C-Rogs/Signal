import SwiftUI

struct DashboardRecoveryCard: View {
    let score: RecoveryScore
    let rollingMeans: MetricRollingMeans
    let window: RecoveryWindow
    let hrvChartRange: ClosedRange<Double>?

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

            Text(DashboardFormatting.recoveryScore(score.value))
                .font(.metricValue)
                .foregroundStyle(scoreColor)

            Text(classificationSubtitle)
                .font(.metadataCaption)
                .fontWeight(.medium)
                .foregroundStyle(classificationColor)

            if let analysis = score.hrvAnalysis,
               score.hrvClassification != .insufficientData,
               let chartRange = hrvChartRange
            {
                HRVBandIndicator(analysis: analysis, chartRange: chartRange)
            }

            confidenceLine

            VStack(alignment: .leading, spacing: 6) {
                baselineRow(
                    label: "HRV today",
                    today: DashboardFormatting.hrv(score.todayHRV),
                    baseline: baselineHRVText
                )
                baselineRow(
                    label: "Resting HR",
                    today: DashboardFormatting.heartRate(score.todayRestingHR),
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
            .foregroundStyle(scoreColor)
            .background(scoreColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var statusTitle: String {
        switch score.value {
        case 70...: "Recovered"
        case 45..<70: "Steady"
        default: "Fatigued"
        }
    }

    private var scoreColor: Color {
        switch score.value {
        case 70...: Color("Positive")
        case 45..<70: Color("Primary")
        default: Color("Warning")
        }
    }

    private var classificationSubtitle: String {
        switch score.hrvClassification {
        case .aboveUpperBand: "Elevated"
        case .withinBand: "Normal"
        case .belowLowerBand: "Suppressed"
        case .insufficientData: "Building baseline..."
        }
    }

    private var classificationColor: Color {
        switch score.hrvClassification {
        case .aboveUpperBand: Color("Positive")
        case .withinBand: Color("TextSecondary")
        case .belowLowerBand: Color("Warning")
        case .insufficientData: Color("TextSecondary")
        }
    }

    private var confidenceLine: some View {
        let points = score.hrvAnalysis?.dataPointsUsed ?? 0
        return Text("Confidence \(score.confidence.rawValue) · \(points) HRV days")
            .font(.metadataCaption)
            .foregroundStyle(Color("TextSecondary"))
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
