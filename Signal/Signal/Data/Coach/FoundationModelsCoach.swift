import Foundation
import FoundationModels
import SwiftData
import os

actor FoundationModelsCoach: LLMCoach {
    private let modelContainer: ModelContainer
    private var responding = false

    var isResponding: Bool {
        responding
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
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

    func respond(to query: String, context: CoachContext) async throws -> AsyncThrowingStream<String, Error> {
        guard !responding else {
            throw CoachError.busy
        }
        guard await FoundationModelsInferenceGate.shared.tryAcquire() else {
            throw CoachError.busy
        }

        responding = true

        let route = CoachQueryRouter.classify(query)
        var workingContext = context
        workingContext.prepareForModelInput(query: query, route: route)
        let initialPrompt = workingContext.assembledPrompt(query: query)
        let sectionNames = workingContext.activeSectionNames().joined(separator: ",")

        let container = modelContainer
        return AsyncThrowingStream { continuation in
            Task {
                var prompt = initialPrompt
                var didRetryAfterOverflow = false
                var rateLimitRetries = 0

                while true {
                    do {
                        let session = CoachSessionFactory.makeSession(
                            modelContainer: container,
                            referenceDate: Date(),
                            query: query,
                            route: route
                        )
                        guard !session.isResponding else {
                            throw CoachError.busy
                        }
                        await MainActor.run {
                            Log.coach.info(
                                "coach stream start intent=\(route.rawValue, privacy: .public) contextSections=\(sectionNames, privacy: .public) promptChars=\(prompt.count, privacy: .public)"
                            )
                        }
                        let stream = session.streamResponse(to: prompt)
                        var previousLength = 0
                        for try await snapshot in stream {
                            let fullText = snapshot.content
                            guard fullText.count > previousLength else { continue }
                            let start = fullText.index(fullText.startIndex, offsetBy: previousLength)
                            let delta = String(fullText[start...])
                            previousLength = fullText.count
                            continuation.yield(delta)
                        }
                        await self.endSession()
                        continuation.finish()
                        return
                    } catch let error as LanguageModelSession.GenerationError {
                        switch error {
                        case .exceededContextWindowSize:
                            guard !didRetryAfterOverflow else {
                                await self.endSession()
                                continuation.finish(throwing: CoachError.contextTooLarge)
                                return
                            }
                            didRetryAfterOverflow = true
                            workingContext.dropOldestHalfOfRAGSummaries()
                            workingContext.prepareForModelInput(query: query, route: route)
                            prompt = workingContext.assembledPrompt(query: query)
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

    private func endSession() async {
        await FoundationModelsInferenceGate.shared.release()
        responding = false
    }

    nonisolated private static func isRateLimitError(_ error: Error) -> Bool {
        error.localizedDescription.lowercased().contains("rate limit")
    }

}
