import SwiftData
import SwiftUI

struct ChatView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ChatViewModel
    @State private var draftText = ""
    @State private var thinkingPulse = false
    @FocusState private var isInputFocused: Bool

    private static let suggestions = [
        "How did I recover this week?",
        "What should I train today?",
        "Am I hitting my protein goals?",
        "Show my squat progress.",
    ]

    init(modelContainer: ModelContainer) {
        _viewModel = State(initialValue: ChatViewModel(modelContainer: modelContainer))
    }

    var body: some View {
        ZStack {
            screenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                messageList
                inputRow
            }
        }
        .navigationTitle("Signal Coach")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Insights") {
                    InsightsView()
                }
            }
        }
        .onAppear {
            viewModel.prewarm()
            Task {
                _ = await CalendarEventStore.shared.requestAccessIfNeeded()
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if viewModel.messages.isEmpty && !viewModel.isThinking {
                        emptyState
                    }

                    ForEach(viewModel.messages) { message in
                        ChatMessageBubble(
                            message: message,
                            onFeedback: { rating in
                                viewModel.submitFeedback(
                                    messageID: message.id,
                                    rating: rating,
                                    modelContext: modelContext
                                )
                            }
                        )
                        .id(message.id)
                    }

                    if viewModel.isThinking {
                        thinkingBubble
                    }

                    if !viewModel.streamingText.isEmpty {
                        ChatAssistantBubble(text: viewModel.streamingText)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.streamingText) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isThinking) { _, isThinking in
                if isThinking {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        thinkingPulse = true
                    }
                } else {
                    thinkingPulse = false
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ask me anything about your training and recovery.")
                .font(.metadataCaption)
                .foregroundStyle(Color("TextSecondary"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            FlowLayout(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button {
                        draftText = suggestion
                    } label: {
                        Text(suggestion)
                            .font(.metadataCaption)
                            .foregroundStyle(Color("TextPrimary"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color("Surface"))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var thinkingBubble: some View {
        ChatAssistantBubble(text: "Thinking...")
            .opacity(thinkingPulse ? 0.45 : 1)
    }

    private var inputRow: some View {
        HStack(spacing: 12) {
            TextField("Ask Signal...", text: $draftText, axis: .vertical)
                .lineLimit(1 ... 4)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color("Surface"))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(Color("TextPrimary"))

            Button {
                submitDraft()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color("Primary") : Color("TextSecondary"))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(screenBackground)
    }

    private var canSend: Bool {
        !viewModel.isThinking && viewModel.streamingText.isEmpty && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitDraft() {
        let text = draftText
        draftText = ""
        isInputFocused = false
        viewModel.sendMessage(text)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }
}

private struct ChatMessageBubble: View {
    let message: ChatMessage
    let onFeedback: (FeedbackRating) -> Void

    var body: some View {
        switch message.role {
        case .user:
            ChatUserBubble(text: message.text, timestamp: message.timestamp)
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                ChatAssistantBubble(text: message.text)
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(Color("TextSecondary"))
                feedbackRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var feedbackRow: some View {
        HStack(spacing: 16) {
            feedbackButton(
                rating: .thumbsUp,
                systemName: message.feedbackRating == .thumbsUp ? "hand.thumbsup.fill" : "hand.thumbsup"
            )
            feedbackButton(
                rating: .thumbsDown,
                systemName: message.feedbackRating == .thumbsDown ? "hand.thumbsdown.fill" : "hand.thumbsdown"
            )
        }
    }

    private func feedbackButton(rating: FeedbackRating, systemName: String) -> some View {
        Button {
            onFeedback(rating)
        } label: {
            Image(systemName: systemName)
                .font(.body)
                .foregroundStyle(Color("TextSecondary"))
        }
        .buttonStyle(.plain)
    }
}

private struct ChatUserBubble: View {
    let text: String
    let timestamp: Date

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color("Primary"))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(Color("TextSecondary"))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct ChatAssistantBubble: View {
    let text: String

    var body: some View {
        Text(displayText)
            .font(.body)
            .foregroundStyle(Color("TextPrimary"))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color("Surface"))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayText: AttributedString {
        CoachMessageFormatting.attributedMarkdown(text)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    NavigationStack {
        ChatView(modelContainer: try! SignalModelContainer.make(inMemoryOnly: true))
    }
    .modelContainer(try! SignalModelContainer.make(inMemoryOnly: true))
}
