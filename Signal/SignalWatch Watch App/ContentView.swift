import SwiftUI

struct ContentView: View {
    var receiver: WatchConnectivityReceiver
    @Bindable var workoutManager: WatchLiveWorkoutSessionManager

    var body: some View {
        Group {
            if workoutManager.isWorkoutActive {
                activeWorkoutContent
            } else if let status = workoutManager.statusMessage {
                statusContent(status)
            } else if let payload = receiver.payload {
                recoveryContent(payload: payload)
            } else {
                waitingContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: receiver.payload?.scoreInt) { _, score in
            guard score != nil else { return }
            WatchComplicationRefresh.reloadTimelineOnly()
        }
    }

    private var activeWorkoutContent: some View {
        ZStack {
            LiveHeartRateDecor(accent: WatchTrainPalette.accent)
                .frame(width: 96, height: 76)
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: LiveHeartRateIcon.liveSymbol)
                        .font(.caption2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(WatchTrainPalette.accent)
                    Text("Train")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let bpm = workoutManager.latestHeartRateBPM {
                    Text("\(bpm)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("BPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: LiveHeartRateIcon.liveSymbol)
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(WatchTrainPalette.accent.opacity(0.5))
                        .symbolEffect(.pulse, options: .repeating)
                    Text("Reading heart rate")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(activeWorkoutAccessibilityLabel)
    }

    private var activeWorkoutAccessibilityLabel: String {
        if let bpm = workoutManager.latestHeartRateBPM {
            return "Train workout active, heart rate \(bpm) beats per minute"
        }
        return "Train workout active, waiting for heart rate"
    }

    private func statusContent(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
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

            Text(payload.hrvBandDisplayLabel)
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

    private func updatedLabel(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return "Updated \(relative)"
    }
}

#Preview {
    ContentView(
        receiver: WatchConnectivityReceiver(),
        workoutManager: WatchLiveWorkoutSessionManager.shared
    )
}
