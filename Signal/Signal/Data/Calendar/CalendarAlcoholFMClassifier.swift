import Foundation
import FoundationModels
import os

enum CalendarAlcoholFMClassifier {
    @Generable
    struct Classification {
        @Guide(description: "Whether the calendar event title suggests social drinking")
        var alcoholLikely: Bool

        @Guide(description: "Confidence from 0 to 1")
        var confidence: Double

        @Guide(description: "Brief reason for the classification")
        var reason: String
    }

    static func classify(
        eventTitle: String,
        shortSleepLastNight: Bool
    ) async -> (confidence: Double, reason: String)? {
        guard CoachModelAvailabilityFormatter.currentStatus().canAskCoach else {
            Log.calendar.info("calendar FM classify skipped model unavailable")
            return nil
        }
        guard let result = await FoundationModelsInferenceGate.shared.withExclusiveAccess({
            await Self.classifyWithSession(
                eventTitle: eventTitle,
                shortSleepLastNight: shortSleepLastNight
            )
        }) else {
            Log.calendar.info("calendar FM classify skipped gate busy")
            return nil
        }
        return result
    }

    private static func classifyWithSession(
        eventTitle: String,
        shortSleepLastNight: Bool
    ) async -> (confidence: Double, reason: String)? {
        let instructions = """
            Classify whether a calendar event title likely refers to social drinking or alcohol.
            Be conservative. Work meetings, medical appointments, gym, and travel are not alcohol.
            Never diagnose medical conditions.
            """

        let prompt = """
            Calendar event title: "\(eventTitle)"
            Does this title suggest the person was out socially drinking last night?
            """

        do {
            let session = LanguageModelSession(instructions: instructions)
            guard !session.isResponding else {
                Log.calendar.info("calendar FM classify skipped session busy")
                return nil
            }
            let response = try await session.respond(
                to: prompt,
                generating: Classification.self
            )
            let result = response.content
            guard result.alcoholLikely else {
                Log.calendar.info(
                    "calendar FM classify alcoholLikely=false reason=\(result.reason, privacy: .public)"
                )
                return nil
            }

            var confidence = min(
                CalendarDisruptorHeuristics.fmMaximumConfidence,
                max(CalendarDisruptorHeuristics.fmMinimumConfidence, result.confidence)
            )
            if shortSleepLastNight {
                confidence = min(
                    CalendarDisruptorHeuristics.fmShortSleepBonusCap,
                    confidence + CalendarDisruptorHeuristics.fmShortSleepBonus
                )
            }
            Log.calendar.info(
                "calendar FM classify alcoholLikely=true confidence=\(confidence, privacy: .public)"
            )
            return (confidence, result.reason)
        } catch {
            Log.calendar.error(
                "calendar FM classify failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}
