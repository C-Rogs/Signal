import Foundation
import FoundationModels
import SwiftData
import os

actor FoundationModelsCoach: LLMCoach {
    private let modelContainer: ModelContainer
    private var responding = false
    private var activeSession: LanguageModelSession?
    private var pinnedThreadRoute: CoachQueryRoute?
    private var instructionsCharCount = 0
    private var lastUsageSnapshot = CoachContextUsageSnapshot.empty

    var isResponding: Bool {
        responding
    }

    var contextUsage: CoachContextUsageSnapshot {
        lastUsageSnapshot
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func hasActiveThread() -> Bool {
        activeSession != nil && CoachFeatureFlags.current().conversationMemoryEnabled
    }

    func threadRoute() -> CoachQueryRoute? {
        pinnedThreadRoute
    }

    func contextUsage(nextPrompt: String) -> CoachContextUsageSnapshot {
        let transcriptChars = transcriptCharacterCount()
        let snapshot = CoachContextBudget.snapshot(
            instructionsChars: instructionsCharCount,
            transcriptChars: transcriptChars,
            nextPromptChars: nextPrompt.count
        )
        lastUsageSnapshot = snapshot
        return snapshot
    }

    func resetThread() {
        activeSession = nil
        pinnedThreadRoute = nil
        instructionsCharCount = 0
        lastUsageSnapshot = .empty
        Log.coach.info("coach thread reset")
    }

    func compactThread(messages: [ChatMessage]) async throws -> CoachCompactResult {
        guard !responding else {
            throw CoachError.busy
        }
        guard await FoundationModelsInferenceGate.shared.tryAcquire() else {
            throw CoachError.busy
        }

        responding = true
        defer {
            responding = false
            Task { await FoundationModelsInferenceGate.shared.release() }
        }

        let conversation = CoachTranscriptText.fromMessages(messages)
        let charsBefore = conversation.count
        let summary = try await CoachThreadCompactor.summarizeConversation(conversation)
        let trimmed = CoachThreadCompactor.trimmedMessages(summary: summary, from: messages)

        let flags = CoachFeatureFlags.current()
        let route = pinnedThreadRoute ?? .general
        let instructions = CoachSessionFactory.makeInstructions(
            referenceDate: Date(),
            route: route,
            flags: flags,
            threadKind: .newThread,
            compactSummary: summary
        )
        instructionsCharCount = instructions.count

        activeSession = CoachSessionFactory.makeSession(
            modelContainer: modelContainer,
            referenceDate: Date(),
            route: route,
            flags: flags,
            threadKind: .newThread,
            compactSummary: summary
        )
        pinnedThreadRoute = route

        let charsAfter = instructionsCharCount + CoachTranscriptText.characterCount(from: trimmed)
        Log.coach.info(
            "coach compact charsBefore=\(charsBefore, privacy: .public) charsAfter=\(charsAfter, privacy: .public)"
        )

        refreshUsageSnapshot(nextPrompt: "")
        return CoachCompactResult(summary: summary, messages: trimmed)
    }

    func prewarm() async {
        let container = modelContainer
        await Task.detached(priority: .utility) {
            let session = CoachSessionFactory.makeSession(modelContainer: container, query: "")
            session.prewarm(promptPrefix: nil)
            await MainActor.run {
                Log.coach.info("coach prewarm finished")
            }
        }.value
    }

    func respond(
        to query: String,
        context: CoachContext,
        threadKind: CoachThreadKind
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard !responding else {
            throw CoachError.busy
        }
        guard await FoundationModelsInferenceGate.shared.tryAcquire() else {
            throw CoachError.busy
        }

        responding = true

        let flags = CoachFeatureFlags.current()
        let effectiveKind = effectiveThreadKind(threadKind, flags: flags)
        var workingContext = context
        let route = pinnedRoute(for: effectiveKind, contextRoute: workingContext.route)
        workingContext.prepareForModelInput(query: query, route: route)

        let prompt: String
        switch effectiveKind {
        case .newThread:
            prompt = workingContext.assembledPrompt(query: query)
        case .followUp:
            prompt = query.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let sectionNames = workingContext.activeSectionNames().joined(separator: ",")
        let container = modelContainer

        return AsyncThrowingStream { continuation in
            Task {
                var currentPrompt = prompt
                var didRetryAfterOverflow = false
                var rateLimitRetries = 0

                while true {
                    do {
                        let session = try await self.sessionForTurn(
                            effectiveKind: effectiveKind,
                            modelContainer: container,
                            query: query,
                            route: route,
                            flags: flags
                        )
                        guard !session.isResponding else {
                            throw CoachError.busy
                        }
                        await MainActor.run {
                            Log.coach.info(
                                "coach stream start thread=\(Self.threadLogLabel(effectiveKind), privacy: .public) intent=\(route.rawValue, privacy: .public) smartContext=\(flags.smartContextEnabled, privacy: .public) deepReasoning=\(flags.deepReasoningEnabled && effectiveKind == .newThread, privacy: .public) contextSections=\(sectionNames, privacy: .public) promptChars=\(currentPrompt.count, privacy: .public)"
                            )
                        }
                        let stream = session.streamResponse(to: currentPrompt)
                        var previousLength = 0
                        for try await snapshot in stream {
                            let fullText = snapshot.content
                            guard fullText.count > previousLength else { continue }
                            let start = fullText.index(fullText.startIndex, offsetBy: previousLength)
                            let delta = String(fullText[start...])
                            previousLength = fullText.count
                            continuation.yield(delta)
                        }
                        await self.refreshUsageSnapshot(nextPrompt: "")
                        await self.endSession()
                        continuation.finish()
                        return
                    } catch let error as LanguageModelSession.GenerationError {
                        switch error {
                        case .exceededContextWindowSize:
                            if effectiveKind == .followUp {
                                await self.endSession()
                                continuation.finish(throwing: CoachError.contextTooLarge)
                                return
                            }
                            guard !didRetryAfterOverflow else {
                                await self.endSession()
                                continuation.finish(throwing: CoachError.contextTooLarge)
                                return
                            }
                            didRetryAfterOverflow = true
                            await self.resetActiveSessionOnly()
                            workingContext.dropOldestHalfOfRAGSummaries()
                            workingContext.prepareForModelInput(query: query, route: route)
                            currentPrompt = workingContext.assembledPrompt(query: query)
                            await MainActor.run {
                                Log.coach.info("coach retry after context overflow")
                            }
                            continue
                        case .rateLimited:
                            if rateLimitRetries < 1 {
                                rateLimitRetries += 1
                                let delaySeconds: UInt64 = 8
                                await MainActor.run {
                                    Log.coach.info("coach retry after rate limit attempt=\(rateLimitRetries, privacy: .public)")
                                }
                                try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                                continue
                            }
                            await self.endSession()
                            continuation.finish(throwing: CoachError.rateLimited)
                            return
                        default:
                            if Self.isRateLimitError(error), rateLimitRetries < 1 {
                                rateLimitRetries += 1
                                let delaySeconds: UInt64 = 8
                                await MainActor.run {
                                    Log.coach.info("coach retry after rate limit attempt=\(rateLimitRetries, privacy: .public)")
                                }
                                try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                                continue
                            }
                            await self.endSession()
                            continuation.finish(throwing: CoachError.generationFailed(underlying: error))
                            return
                        }
                    } catch {
                        if Self.isRateLimitError(error), rateLimitRetries < 1 {
                            rateLimitRetries += 1
                            let delaySeconds: UInt64 = 8
                            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                            continue
                        }
                        await self.endSession()
                        continuation.finish(throwing: CoachError.generationFailed(underlying: error))
                        return
                    }
                }
            }
        }
    }

    private func sessionForTurn(
        effectiveKind: CoachThreadKind,
        modelContainer: ModelContainer,
        query: String,
        route: CoachQueryRoute,
        flags: CoachFeatureFlags
    ) throws -> LanguageModelSession {
        switch effectiveKind {
        case .followUp:
            if let activeSession {
                return activeSession
            }
            fallthrough
        case .newThread:
            let instructions = CoachSessionFactory.makeInstructions(
                referenceDate: Date(),
                route: route,
                flags: flags,
                threadKind: .newThread
            )
            instructionsCharCount = instructions.count
            let session = CoachSessionFactory.makeSession(
                modelContainer: modelContainer,
                referenceDate: Date(),
                query: query,
                route: route,
                flags: flags,
                threadKind: .newThread
            )
            activeSession = session
            pinnedThreadRoute = route
            return session
        }
    }

    private func effectiveThreadKind(_ requested: CoachThreadKind, flags: CoachFeatureFlags) -> CoachThreadKind {
        guard flags.conversationMemoryEnabled else { return .newThread }
        if requested == .followUp, activeSession != nil {
            return .followUp
        }
        return .newThread
    }

    private func pinnedRoute(for kind: CoachThreadKind, contextRoute: CoachQueryRoute) -> CoachQueryRoute {
        switch kind {
        case .newThread:
            return contextRoute
        case .followUp:
            return pinnedThreadRoute ?? contextRoute
        }
    }

    private func resetActiveSessionOnly() {
        activeSession = nil
    }

    private func transcriptCharacterCount() -> Int {
        if let activeSession {
            return CoachTranscriptText.characterCount(from: activeSession)
        }
        return 0
    }

    private func refreshUsageSnapshot(nextPrompt: String) {
        let snapshot = CoachContextBudget.snapshot(
            instructionsChars: instructionsCharCount,
            transcriptChars: transcriptCharacterCount(),
            nextPromptChars: nextPrompt.count
        )
        lastUsageSnapshot = snapshot
        Log.coach.info("coach contextTokens=\(snapshot.estimatedTokens, privacy: .public)")
    }

    private func endSession() async {
        await FoundationModelsInferenceGate.shared.release()
        responding = false
    }

    nonisolated private static func isRateLimitError(_ error: Error) -> Bool {
        error.localizedDescription.lowercased().contains("rate limit")
    }

    nonisolated private static func threadLogLabel(_ kind: CoachThreadKind) -> String {
        switch kind {
        case .newThread: "newThread"
        case .followUp: "followUp"
        }
    }
}
