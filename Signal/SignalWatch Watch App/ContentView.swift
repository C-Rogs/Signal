import SwiftUI

struct ContentView: View {
    var receiver: WatchConnectivityReceiver
    var workoutManager: WatchLiveWorkoutSessionManager

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
        .task {
            await workoutManager.prepareOnLaunch()
        }
    }

    private var activeWorkoutContent: some View {
        VStack(spacing: 6) {
            Text("Train")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let bpm = workoutManager.latestHeartRateBPM {
                Text("\(bpm)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.red)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("BPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .padding(.vertical, 8)
                Text("Reading heart rate")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
