import Foundation
import FoundationModels
import SwiftData
import os

actor FoundationModelsCoach: LLMCoach {
    private let modelContainer: ModelContainer
    private var responding = false
    private var activeSession: LanguageModelSession?
    private var pinnedThreadRoute: CoachQueryRoute?
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
        let snapshot = makeUsageSnapshot(nextPrompt: nextPrompt)
        lastUsageSnapshot = snapshot
        return snapshot
    }

    func resetThread() {
        activeSession = nil
        pinnedThreadRoute = nil
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

        activeSession = CoachSessionFactory.makeSession(
            modelContainer: modelContainer,
            referenceDate: Date(),
            route: route,
            flags: flags,
            threadKind: .newThread,
            compactSummary: summary
        )
        pinnedThreadRoute = route

        let charsAfter = instructions.count + CoachTranscriptText.characterCount(from: trimmed)
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
        let route = pinnedRoute(for: effectiveKind, contextRoute: workingContext.route, query: query, flags: flags)
        workingContext.prepareForModelInput(query: query, route: route)

        let prompt: String
        switch effectiveKind {
        case .newThread:
            prompt = workingContext.assembledPrompt(query: query)
        case .followUp:
            var userText = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if CoachQueryIntent.needsScheduleAccess(query: query, pinnedRoute: pinnedThreadRoute) {
                if let summary = await CoachScheduleRefresh.freshSummary() {
                    userText = "Schedule (fresh):\n\(summary)\n\n\(userText)"
                    Log.coach.info(
                        "coach followUp scheduleRefresh tools=calendarSchedule promptChars=\(userText.count, privacy: .public)"
                    )
                }
            }
            prompt = userText
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
                        let session = try self.sessionForTurn(
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
            if let session = activeSession {
                let mergedRoute = CoachSessionFactory.mergedRoute(
                    pinnedRoute: pinnedThreadRoute,
                    query: query,
                    flags: flags
                )
                let neededNames = Set(
                    CoachSessionFactory.toolNames(
                        modelContainer: modelContainer,
                        query: query,
                        route: mergedRoute,
                        flags: flags
                    )
                )
                let currentNames = Set(CoachContextBreakdown.activeToolNames(from: session.transcript))
                if neededNames != currentNames {
                    let tools = CoachSessionFactory.makeTools(
                        modelContainer: modelContainer,
                        query: query,
                        route: mergedRoute,
                        flags: flags
                    )
                    let refreshed = LanguageModelSession(
                        model: .default,
                        tools: tools,
                        transcript: session.transcript
                    )
                    activeSession = refreshed
                    Log.coach.info(
                        "coach followUp toolRefresh tools=\(neededNames.sorted().joined(separator: ","), privacy: .public)"
                    )
                    return refreshed
                }
                return session
            }
            fallthrough
        case .newThread:
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

    private func pinnedRoute(
        for kind: CoachThreadKind,
        contextRoute: CoachQueryRoute,
        query: String,
        flags: CoachFeatureFlags
    ) -> CoachQueryRoute {
        switch kind {
        case .newThread:
            return contextRoute
        case .followUp:
            return CoachSessionFactory.mergedRoute(
                pinnedRoute: pinnedThreadRoute ?? contextRoute,
                query: query,
                flags: flags
            )
        }
    }

    private func resetActiveSessionOnly() {
        activeSession = nil
    }

    private func pendingPromptCharacterCount(_ nextPrompt: String) -> Int {
        let trimmed = nextPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        guard let activeSession else { return trimmed.count }
        let transcriptText = CoachTranscriptText.fromSession(activeSession)
        guard !transcriptText.contains(trimmed) else { return 0 }
        return trimmed.count
    }

    private func makeUsageSnapshot(nextPrompt: String) -> CoachContextUsageSnapshot {
        let pending = pendingPromptCharacterCount(nextPrompt)
        guard let activeSession else {
            return CoachContextBudget.snapshot(
                instructionsChars: 0,
                transcriptChars: 0,
                nextPromptChars: pending
            )
        }
        return CoachContextBreakdown.snapshot(
            transcript: activeSession.transcript,
            pendingPromptChars: pending
        )
    }

    private func refreshUsageSnapshot(nextPrompt: String) {
        let snapshot = makeUsageSnapshot(nextPrompt: nextPrompt)
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
