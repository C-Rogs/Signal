import Foundation
import os

enum CalendarDisruptorMatchTier: String, Sendable, Equatable {
    case userPhrase
    case embedding
    case foundationModel
}

struct CalendarDisruptorCandidate: Sendable, Equatable, Identifiable {
    var id: String { dedupeKey }
    let eventTitle: String
    let eveningStartDay: Date
    let confidence: Double
    let tier: CalendarDisruptorMatchTier
    let dedupeKey: String
}

enum CalendarDisruptorClassifier {
    static func classify(
        events: [CalendarEventSnapshot],
        userPhrases: [String],
        metricSnapshots: [DailyMetricSnapshot],
        referenceDate: Date,
        calendar: Calendar,
        embeddingService: any EmbeddingService = EmbeddingBackend.makeService()
    ) async -> CalendarDisruptorCandidate? {
        let eveningStartDay = CalendarDisruptorLookback.eveningStartDay(
            referenceDate: referenceDate,
            calendar: calendar
        )
        let window = CalendarDisruptorLookback.window(referenceDate: referenceDate, calendar: calendar)
        let windowEvents = CalendarEventFilter.events(in: window, from: events)
        guard !windowEvents.isEmpty else {
            Log.calendar.info("calendar disruptor classify no events in lookback window")
            return nil
        }

        let shortSleep = priorNightShortSleep(
            metricSnapshots: metricSnapshots,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let phraseList = mergedPhraseList(userPhrases: userPhrases)

        var best: CalendarDisruptorCandidate?

        for event in windowEvents {
            guard let candidate = await classifyEvent(
                event,
                phraseList: phraseList,
                eveningStartDay: eveningStartDay,
                calendar: calendar,
                shortSleep: shortSleep,
                embeddingService: embeddingService
            ) else { continue }

            if let currentBest = best {
                if candidate.confidence > currentBest.confidence {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        if let best {
            Log.calendar.info(
                "calendar disruptor candidate title=\(best.eventTitle, privacy: .public) tier=\(best.tier.rawValue, privacy: .public) confidence=\(best.confidence, privacy: .public)"
            )
        }
        return best
    }

    static func mergedPhraseList(userPhrases: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for phrase in userPhrases + CalendarDisruptorHeuristics.builtInSeedPhrases {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            merged.append(trimmed)
        }
        return merged
    }

    private static func classifyEvent(
        _ event: CalendarEventSnapshot,
        phraseList: [String],
        eveningStartDay: Date,
        calendar: Calendar,
        shortSleep: Bool,
        embeddingService: any EmbeddingService
    ) async -> CalendarDisruptorCandidate? {
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        if isBlocklisted(title) {
            Log.calendar.info("calendar disruptor skipped blocklisted title=\(title, privacy: .public)")
            return nil
        }

        if let phraseMatch = phraseMatch(for: event, phraseList: phraseList) {
            return makeCandidate(
                eventTitle: title,
                eveningStartDay: eveningStartDay,
                calendar: calendar,
                confidence: CalendarDisruptorHeuristics.userPhraseMatchConfidence,
                tier: .userPhrase,
                matchedPhrase: phraseMatch
            )
        }

        if let embeddingMatch = await embeddingMatch(
            title: title,
            phraseList: phraseList,
            embeddingService: embeddingService
        ) {
            return makeCandidate(
                eventTitle: title,
                eveningStartDay: eveningStartDay,
                calendar: calendar,
                confidence: CalendarDisruptorHeuristics.embeddingMatchConfidence,
                tier: .embedding,
                matchedPhrase: embeddingMatch
            )
        }

        if let fmResult = await CalendarAlcoholFMClassifier.classify(
            eventTitle: title,
            shortSleepLastNight: shortSleep
        ) {
            return makeCandidate(
                eventTitle: title,
                eveningStartDay: eveningStartDay,
                calendar: calendar,
                confidence: fmResult.confidence,
                tier: .foundationModel,
                matchedPhrase: fmResult.reason
            )
        }

        return nil
    }

    private static func makeCandidate(
        eventTitle: String,
        eveningStartDay: Date,
        calendar: Calendar,
        confidence: Double,
        tier: CalendarDisruptorMatchTier,
        matchedPhrase: String
    ) -> CalendarDisruptorCandidate {
        _ = matchedPhrase
        return CalendarDisruptorCandidate(
            eventTitle: eventTitle,
            eveningStartDay: eveningStartDay,
            confidence: confidence,
            tier: tier,
            dedupeKey: CalendarDisruptorHeuristics.calendarInferredDedupeKey(
                eveningStartDay: eveningStartDay,
                calendar: calendar
            )
        )
    }

    private static func phraseMatch(for event: CalendarEventSnapshot, phraseList: [String]) -> String? {
        let searchable = searchableText(for: event)
        for phrase in phraseList {
            let normalizedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedPhrase.isEmpty else { continue }
            if searchable.contains(normalizedPhrase) {
                return phrase
            }
        }
        return nil
    }

    private static func searchableText(for event: CalendarEventSnapshot) -> String {
        var parts = [event.title]
        if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append(notes)
        }
        return parts.joined(separator: " ").lowercased()
    }

    private static func isBlocklisted(_ title: String) -> Bool {
        let lower = title.lowercased()
        return CalendarDisruptorHeuristics.titleBlocklist.contains { lower.contains($0) }
    }

    private static func embeddingMatch(
        title: String,
        phraseList: [String],
        embeddingService: any EmbeddingService
    ) async -> String? {
        do {
            await EmbeddingRunPolicy.waitUntilMayUseMetal()
            let titleVector = try await embeddingService.embed(title, kind: .document)
            var bestPhrase: String?
            var bestScore: Float = 0

            for phrase in phraseList {
                let seedVector = try await embeddingService.embed(phrase, kind: .document)
                guard let score = CosineSimilarity.score(query: titleVector, candidate: seedVector) else {
                    continue
                }
                if score > bestScore {
                    bestScore = score
                    bestPhrase = phrase
                }
            }

            guard bestScore >= CalendarDisruptorHeuristics.embeddingSimilarityThreshold,
                  let bestPhrase
            else { return nil }

            Log.calendar.info(
                "calendar embedding match phrase=\(bestPhrase, privacy: .public) score=\(bestScore, privacy: .public)"
            )
            return bestPhrase
        } catch {
            Log.calendar.error(
                "calendar embedding match failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private static func priorNightShortSleep(
        metricSnapshots: [DailyMetricSnapshot],
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        let priorDay = CalendarDisruptorLookback.eveningStartDay(
            referenceDate: referenceDate,
            calendar: calendar
        )
        guard let priorMetric = metricSnapshots.first(where: { calendar.isDate($0.date, inSameDayAs: priorDay) }),
              let sleepHours = priorMetric.sleepHours
        else { return false }
        return sleepHours < RecoveryDisruptorHeuristics.alcoholProxySleepHoursMax
    }
}
