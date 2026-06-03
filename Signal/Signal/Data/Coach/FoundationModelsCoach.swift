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
            let session = CoachSessionFactory.makeSession(modelContainer: container)
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
        responding = true

        var workingContext = context
        workingContext.prepareForModelInput(query: query)
        let initialPrompt = workingContext.assembledPrompt(query: query)

        let container = modelContainer
        return AsyncThrowingStream { continuation in
            Task {
                var prompt = initialPrompt
                var didRetryAfterOverflow = false

                defer {
                    Task { await self.clearResponding() }
                }

                while true {
                    do {
                        let session = CoachSessionFactory.makeSession(modelContainer: container)
                        guard !session.isResponding else {
                            throw CoachError.busy
                        }
                        await MainActor.run {
                            Log.coach.info("coach stream start promptChars=\(prompt.count, privacy: .public)")
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
                        continuation.finish()
                        return
                    } catch let error as LanguageModelSession.GenerationError {
                        switch error {
                        case .exceededContextWindowSize:
                            guard !didRetryAfterOverflow else {
                                continuation.finish(throwing: CoachError.contextTooLarge)
                                return
                            }
                            didRetryAfterOverflow = true
                            workingContext.dropOldestHalfOfRAGSummaries()
                            workingContext.prepareForModelInput(query: query)
                            prompt = workingContext.assembledPrompt(query: query)
                            await MainActor.run {
                                Log.coach.info("coach retry after context overflow")
                            }
                            continue
                        case .rateLimited:
                            continuation.finish(throwing: CoachError.rateLimited)
                            return
                        default:
                            continuation.finish(throwing: CoachError.generationFailed(underlying: error))
                            return
                        }
                    } catch {
                        continuation.finish(throwing: CoachError.generationFailed(underlying: error))
                        return
                    }
                }
            }
        }
    }

    private func clearResponding() {
        responding = false
    }

}
