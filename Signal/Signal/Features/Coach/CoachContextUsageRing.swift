import SwiftUI

struct CoachContextUsageRing: View {
    let usage: CoachContextUsageSnapshot
    var showsPlaceholder = false

    private var ringColor: Color {
        if usage.isOverLimit {
            return .red
        }
        if usage.isNearLimit {
            return .orange
        }
        return Color("Primary")
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color("TextSecondary").opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: showsPlaceholder ? 0 : usage.fractionUsed)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: usage.fractionUsed)
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel("Context usage")
        .accessibilityValue("\(usage.estimatedTokens) of \(usage.maxTokens) tokens")
    }
}

struct CoachContextUsageSheet: View {
    let usage: CoachContextUsageSnapshot
    let conversationMemoryEnabled: Bool
    let onCompact: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    CoachContextUsageRing(usage: usage)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Context ~\(usage.estimatedTokens) / \(usage.maxTokens) tokens")
                            .font(.headline)
                            .foregroundStyle(Color("TextPrimary"))
                        Text("On-device model window. Turn 1 loads your health data; follow-ups use the transcript.")
                            .font(.metadataCaption)
                            .foregroundStyle(Color("TextSecondary"))
                    }
                }

                if !conversationMemoryEnabled {
                    Text("Conversation memory is off. Each message starts fresh with full context.")
                        .font(.metadataCaption)
                        .foregroundStyle(Color("TextSecondary"))
                } else if usage.isNearLimit {
                    Text("Context is filling up. Compact to summarize earlier turns and keep refining your plan.")
                        .font(.metadataCaption)
                        .foregroundStyle(Color("TextSecondary"))

                    Button {
                        dismiss()
                        onCompact()
                    } label: {
                        Text("Compact conversation")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("Primary"))
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
