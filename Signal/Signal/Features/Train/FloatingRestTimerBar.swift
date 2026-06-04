import SwiftUI

struct FloatingRestTimerBar: View {
    let exerciseTitle: String
    let remainingSeconds: Int
    var autoregulationNotice: String?
    let onSkip: () -> Void
    let onSubtract15: () -> Void
    let onAdd15: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let autoregulationNotice {
                Text(autoregulationNotice)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color("Warning"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("dynamicRestNotice")
            }
            HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color("TextSecondary"))
                Text(exerciseTitle)
                    .font(.caption)
                    .foregroundStyle(Color("TextPrimary"))
                    .lineLimit(1)
            }
            Text(formattedRemaining)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color("Primary"))
                .frame(minWidth: 64, alignment: .leading)
            Spacer(minLength: 0)
            restControl("Skip", action: onSkip)
            restControl("-15s", action: onSubtract15)
            restControl("+15s", action: onAdd15)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color("Surface"))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rest timer \(formattedRemaining) for \(exerciseTitle)")
    }

    private var formattedRemaining: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func restControl(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(Color("Primary"))
    }
}
