import SwiftUI

struct LiveWorkoutBanner: View {
    @Environment(LiveWorkoutCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: AppTab

    var body: some View {
        if coordinator.activeSession != nil {
            Button {
                selectedTab = .train
                coordinator.resumeWorkout()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.body.weight(.semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workout in progress")
                            .font(.subheadline.weight(.semibold))
                        Text(coordinator.activeSession?.title ?? "Workout")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(elapsedText(since: coordinator.activeSession?.startTime ?? .now))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(bannerBackground)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("liveWorkoutBanner")
        }
    }

    private var bannerBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.95)
    }

    private func elapsedText(since start: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
