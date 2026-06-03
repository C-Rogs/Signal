import SwiftUI

struct ContentView: View {
    var receiver: WatchConnectivityReceiver

    var body: some View {
        VStack(spacing: 6) {
            if let payload = receiver.payload {
                recoveryContent(payload: payload)
            } else {
                waitingContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var waitingContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("Waiting for Signal")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private func recoveryContent(payload: WatchPayload) -> some View {
        VStack(spacing: 4) {
            Text("\(payload.scoreInt)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(for: payload.recoveryScore))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(hrvLabel(for: payload.hrvClassification))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(updatedLabel(for: payload.lastUpdated))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func scoreColor(for score: Double) -> Color {
        if score >= 70 { return .green }
        if score >= 40 { return .orange }
        return .red
    }

    private func hrvLabel(for rawValue: String) -> String {
        switch rawValue {
        case "aboveUpperBand":
            "Above Baseline"
        case "withinBand":
            "Within Range"
        case "belowLowerBand":
            "Below Baseline"
        default:
            "Tracking..."
        }
    }

    private func updatedLabel(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return "Updated \(relative)"
    }
}

#Preview {
    ContentView(receiver: WatchConnectivityReceiver())
}
