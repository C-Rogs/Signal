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
                .stroke(Color("TextSecondary").opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: showsPlaceholder ? 0 : usage.fractionUsed)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: usage.fractionUsed)
        }
        .padding(2)
        .frame(width: 28, height: 28)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        CoachContextUsageRing(usage: usage)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Context ~\(usage.estimatedTokens) / \(usage.maxTokens) tokens")
                                .font(.headline)
                                .foregroundStyle(Color("TextPrimary"))
                            Text("On-device model window. Turn 1 loads your health data; follow-ups add to the transcript.")
                                .font(.metadataCaption)
                                .foregroundStyle(Color("TextSecondary"))
                        }
                    }

                    if !usage.breakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Breakdown")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color("TextPrimary"))
                            ForEach(usage.breakdown) { row in
                                HStack {
                                    Text(row.label)
                                        .foregroundStyle(Color("TextPrimary"))
                                    Spacer()
                                    Text("~\(row.estimatedTokens)")
                                        .foregroundStyle(Color("TextSecondary"))
                                        .monospacedDigit()
                                }
                                .font(.metadataCaption)
                            }
                        }
                    }

                    if !usage.activeToolNames.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active tools")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color("TextPrimary"))
                            Text(usage.activeToolNames.joined(separator: ", "))
                                .font(.metadataCaption)
                                .foregroundStyle(Color("TextSecondary"))
                        }
                    }

                    if !conversationMemoryEnabled {
                        Text("Conversation memory is off. Each message starts fresh with full context.")
                            .font(.metadataCaption)
                            .foregroundStyle(Color("TextSecondary"))
                    } else if usage.isNearLimit || usage.isOverLimit {
                        Text(compactGuidance)
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
                        .tint(usage.isOverLimit ? .red : Color("Primary"))
                    }
                }
                .padding(20)
            }
            .navigationTitle("Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var compactGuidance: String {
        if usage.isOverLimit {
            return "Context is nearly full. Compact now to summarize earlier turns and keep refining your plan."
        }
        return "Context is filling up. Compact to summarize earlier turns and keep refining your plan."
    }
}
