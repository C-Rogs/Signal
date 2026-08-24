import Foundation
import FoundationModels
import Observation
import SwiftData
import os

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var isThinking = false
    var streamingText = ""
    var errorMessage: String?
    var contextUsage = CoachContextUsageSnapshot.empty

    private let modelContainer: ModelContainer
    private let coach: any LLMCoach
    private let buildContext: @Sendable (String, ModelContainer) async throws -> CoachContext
    private var sendInFlight = false
    private var activeSendTask: Task<Void, Never>?
    private var conversationMemoryEnabled: Bool

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.conversationMemoryEnabled = CoachFeatureFlags.current().conversationMemoryEnabled
        let contextBuilder = CoachContextBuilder()
        let coach = FoundationModelsCoach(modelContainer: modelContainer)
        self.coach = coach
        self.buildContext = { query, container in
            try await contextBuilder.buildContext(for: query, modelContainer: container)
        }
    }

    init(
        modelContainer: ModelContainer,
        coach: any LLMCoach,
        buildContext: @escaping @Sendable (String, ModelContainer) async throws -> CoachContext,
        conversationMemoryEnabled: Bool = CoachFeatureFlags.current().conversationMemoryEnabled
    ) {
        self.modelContainer = modelContainer
        self.coach = coach
        self.buildContext = buildContext
        self.conversationMemoryEnabled = conversationMemoryEnabled
    }

    func prewarm() {
        let container = modelContainer
        Task.detached(priority: .utility) {
            let session = CoachSessionFactory.makeSession(modelContainer: container)
            session.prewarm(promptPrefix: nil)
            await MainActor.run {
                Log.coach.info("chat prewarm finished")
            }
        }
    }

    func updateConversationMemoryEnabled(_ enabled: Bool) {
        conversationMemoryEnabled = enabled
        if !enabled {
            Task { await coach.resetThread() }
            contextUsage = .empty
        }
    }

    func abandonActiveWork() async {
        await coach.abandonActiveWork()
    }

    func cancelActiveWork() {
        activeSendTask?.cancel()
        activeSendTask = nil
        sendInFlight = false
        isThinking = false
        streamingText = ""
        Task {
            await abandonActiveWork()
        }
    }

    func startNewConversation() {
        activeSendTask?.cancel()
        sendInFlight = false
        isThinking = false
        streamingText = ""
        errorMessage = nil
        messages = []
        Task {
            await coach.resetThread()
            await refreshContextUsage(nextPrompt: "")
        }
    }

    func compactConversation() {
        guard conversationMemoryEnabled else { return }
        guard !sendInFlight else { return }

        sendInFlight = true
        isThinking = true
        errorMessage = nil

        activeSendTask?.cancel()
        activeSendTask = Task { [weak self] in
            await self?.performCompact()
        }
    }

    func sendMessage(_ rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !sendInFlight else { return }

        sendInFlight = true
        errorMessage = nil
        messages.append(ChatMessage(role: .user, text: trimmed))
        isThinking = true

        activeSendTask?.cancel()
        activeSendTask = Task { [weak self] in
            await self?.performSend(query: trimmed, isRetryAfterAutoCompact: false)
        }
    }

    func submitFeedback(
        messageID: UUID,
        rating: FeedbackRating,
        modelContext: ModelContext
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].role == .assistant,
              !messages[index].isCompactSummary,
              !messages[index].isSystemNotice
        else { return }

        messages[index].feedbackRating = rating
        let responseText = messages[index].text
        let query = messages[index].promptQuery ?? ""
        let excerpt = String(responseText.prefix(300))

        let messageIDValue = messageID
        var descriptor = FetchDescriptor<ChatFeedback>(
            predicate: #Predicate { $0.messageID == messageIDValue }
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.rating = rating
            existing.responseExcerpt = excerpt
            existing.query = query
        } else {
            modelContext.insert(
                ChatFeedback(
                    messageID: messageID,
                    query: query,
                    responseExcerpt: excerpt,
                    rating: rating
                )
            )
        }

        try? modelContext.save()
        let queryPrefix = String(query.prefix(80))
        Log.coach.info("chat feedback rating=\(rating.rawValue, privacy: .public) queryPrefix=\(queryPrefix, privacy: .public)")
    }

    private func performCompact() async {
        defer {
            sendInFlight = false
            isThinking = false
        }

        do {
            let result = try await coach.compactThread(messages: messages)
            guard !Task.isCancelled else { return }
            messages = result.messages
            await refreshContextUsage(nextPrompt: "")
        } catch let error as CoachError {
            errorMessage = Self.assistantMessage(for: error)
        } catch {
            if error is CancellationError { return }
            errorMessage = Self.assistantMessage(for: error)
        }
    }

    private func performSend(query: String, isRetryAfterAutoCompact: Bool) async {
        defer {
            sendInFlight = false
            isThinking = false
        }

        do {
            let threadKind = await resolveThreadKind()
            let context: CoachContext
            if threadKind == .followUp, let route = await coach.threadRoute() {
                context = CoachContext.followUpPlaceholder(route: route)
            } else {
                context = try await buildContext(query, modelContainer)
            }
            guard !Task.isCancelled else { return }

            await refreshContextUsage(nextPrompt: query)
            isThinking = false
            let stream = try await coach.respond(to: query, context: context, threadKind: threadKind)
            guard !Task.isCancelled else {
                streamingText = ""
                return
            }

            do {
                for try await chunk in stream {
                    guard !Task.isCancelled else {
                        streamingText = ""
                        return
                    }
                    streamingText += chunk
                }
            } catch let error as CoachError {
                if case .contextTooLarge = error,
                   conversationMemoryEnabled,
                   !isRetryAfterAutoCompact {
                    await attemptAutoCompactAndRetry(query: query)
                    return
                }
                handleCoachError(error, query: query)
                return
            } catch {
                handleFailure(Self.assistantMessage(for: error), query: query)
                return
            }

            let completed = streamingText
            streamingText = ""
            guard !completed.isEmpty else { return }
            messages.append(ChatMessage(role: .assistant, text: completed, promptQuery: query))
            await refreshContextUsage(nextPrompt: "")
        } catch let error as CoachError {
            if case .contextTooLarge = error,
               conversationMemoryEnabled,
               !isRetryAfterAutoCompact {
                await attemptAutoCompactAndRetry(query: query)
                return
            }
            handleCoachError(error, query: query)
        } catch {
            if error is CancellationError { return }
            handleFailure(Self.assistantMessage(for: error), query: query)
        }
    }

    private func attemptAutoCompactAndRetry(query: String) async {
        Log.coach.info("coach autoCompact reason=contextOverflow")
        do {
            let result = try await coach.compactThread(messages: messages)
            guard !Task.isCancelled else { return }
            messages = result.messages
            messages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Context was compacted automatically so we could keep going.",
                    isSystemNotice: true
                )
            )
            await refreshContextUsage(nextPrompt: "")
            await performSend(query: query, isRetryAfterAutoCompact: true)
        } catch {
            handleCoachError(.contextTooLarge, query: query)
        }
    }

    private func resolveThreadKind() async -> CoachThreadKind {
        guard conversationMemoryEnabled else { return .newThread }
        if await coach.hasActiveThread() {
            return .followUp
        }
        return .newThread
    }

    private func refreshContextUsage(nextPrompt: String) async {
        guard conversationMemoryEnabled else {
            contextUsage = .empty
            return
        }
        contextUsage = await coach.contextUsage(nextPrompt: nextPrompt)
    }

    private func handleCoachError(_ error: CoachError, query: String) {
        let text = Self.assistantMessage(for: error)
        errorMessage = text
        streamingText = ""
        isThinking = false
        messages.append(ChatMessage(role: .assistant, text: text, promptQuery: query))
    }

    private func handleFailure(_ text: String, query: String) {
        errorMessage = text
        streamingText = ""
        isThinking = false
        messages.append(ChatMessage(role: .assistant, text: text, promptQuery: query))
    }

    private static func assistantMessage(for error: Error) -> String {
        if let coachError = error as? CoachError {
            return assistantMessage(for: coachError)
        }
        return "Something went wrong. Try again."
    }

    private static func assistantMessage(for error: CoachError) -> String {
        switch error {
        case .rateLimited:
            return "Signal is cooling down. Try again in a moment."
        case .contextTooLarge:
            return "Context is full. Compact the conversation or start a new one."
        case .compactionFailed:
            return "Could not compact this thread. Try a new conversation."
        case .generationFailed:
            return "Something went wrong. Try again."
        case .busy:
            return "Something went wrong. Try again."
        }
    }
}
