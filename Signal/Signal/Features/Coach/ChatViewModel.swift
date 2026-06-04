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

    private let modelContainer: ModelContainer
    private let buildContext: @Sendable (String, ModelContainer) async throws -> CoachContext
    private let respond: @Sendable (String, CoachContext) async throws -> AsyncThrowingStream<String, Error>
    private var sendInFlight = false
    private var activeSendTask: Task<Void, Never>?
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let contextBuilder = CoachContextBuilder()
        let coach = FoundationModelsCoach(modelContainer: modelContainer)
        self.buildContext = { query, container in
            try await contextBuilder.buildContext(for: query, modelContainer: container)
        }
        self.respond = { query, context in
            try await coach.respond(to: query, context: context)
        }
    }

    init(
        modelContainer: ModelContainer,
        buildContext: @escaping @Sendable (String, ModelContainer) async throws -> CoachContext,
        respond: @escaping @Sendable (String, CoachContext) async throws -> AsyncThrowingStream<String, Error>
    ) {
        self.modelContainer = modelContainer
        self.buildContext = buildContext
        self.respond = respond
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
            await self?.performSend(query: trimmed)
        }
    }

    func submitFeedback(
        messageID: UUID,
        rating: FeedbackRating,
        modelContext: ModelContext
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].role == .assistant
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

    private func performSend(query: String) async {
        defer {
            sendInFlight = false
            isThinking = false
        }

        do {
            _ = await CalendarEventStore.shared.requestAccessIfNeeded()
            let context = try await buildContext(query, modelContainer)
            guard !Task.isCancelled else { return }

            isThinking = false
            let stream = try await respond(query, context)
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
        } catch let error as CoachError {
            handleCoachError(error, query: query)
        } catch {
            if error is CancellationError { return }
            handleFailure(Self.assistantMessage(for: error), query: query)
        }
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
            return "Try a more focused question. Narrower context works better."
        case .generationFailed:
            return "Something went wrong. Try again."
        case .busy:
            return "Something went wrong. Try again."
        }
    }
}
