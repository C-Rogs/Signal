import Foundation
import Testing
@testable import Signal

private struct MockEmbeddingService: EmbeddingService, Sendable {
    let matchedTitles: Set<String>
    let outputDimension = HealthVectorDimension.embeddingGemma

    func embed(_ text: String, kind: EmbeddingKind) async throws -> [Float] {
        _ = kind
        var vector = [Float](repeating: 0, count: outputDimension)
        vector[0] = matchedTitles.contains(text.lowercased()) ? 1 : 0
        return vector
    }

    func embedBatch(_ texts: [String], kind: EmbeddingKind) async throws -> [[Float]] {
        var vectors: [[Float]] = []
        vectors.reserveCapacity(texts.count)
        for text in texts {
            vectors.append(try await embed(text, kind: kind))
        }
        return vectors
    }
}

@MainActor
struct CalendarDisruptorClassifierTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func referenceDate() -> Date {
        calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        )!
    }

    private func event(
        title: String,
        hour: Int,
        dayOffset: Int,
        notes: String? = nil
    ) -> CalendarEventSnapshot {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: referenceDate()))!
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return CalendarEventSnapshot(
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            isAllDay: false,
            notes: notes
        )
    }

    @Test func userPhraseExactMatchOnPubNight() async {
        let ref = referenceDate()
        let events = [event(title: "pub night", hour: 20, dayOffset: -1)]
        let candidate = await CalendarDisruptorClassifier.classify(
            events: events,
            userPhrases: [],
            metricSnapshots: [],
            referenceDate: ref,
            calendar: calendar
        )
        #expect(candidate?.eventTitle == "pub night")
        #expect(candidate?.tier == .userPhrase)
        #expect(candidate?.confidence == CalendarDisruptorHeuristics.userPhraseMatchConfidence)
    }

    @Test func customUserPhraseMatchesNonstandardTitle() async {
        let ref = referenceDate()
        let events = [event(title: "Beer o'clock with Sam", hour: 19, dayOffset: -1)]
        let candidate = await CalendarDisruptorClassifier.classify(
            events: events,
            userPhrases: ["beer o'clock"],
            metricSnapshots: [],
            referenceDate: ref,
            calendar: calendar
        )
        #expect(candidate != nil)
        #expect(candidate?.tier == .userPhrase)
    }

    @Test func dentistTitleDoesNotMatch() async {
        let ref = referenceDate()
        let events = [event(title: "Dentist", hour: 10, dayOffset: -1)]
        let candidate = await CalendarDisruptorClassifier.classify(
            events: events,
            userPhrases: ["pub night"],
            metricSnapshots: [],
            referenceDate: ref,
            calendar: calendar,
            embeddingService: MockEmbeddingService(matchedTitles: ["dentist"])
        )
        #expect(candidate == nil)
    }

    @Test func embeddingMatchUsesMockService() async {
        let ref = referenceDate()
        let events = [event(title: "Neighborhood hangout", hour: 21, dayOffset: -1)]
        let mock = MockEmbeddingService(matchedTitles: ["neighborhood hangout", "pub night"])
        let candidate = await CalendarDisruptorClassifier.classify(
            events: events,
            userPhrases: [],
            metricSnapshots: [],
            referenceDate: ref,
            calendar: calendar,
            embeddingService: mock
        )
        #expect(candidate?.tier == .embedding)
        #expect(candidate?.confidence == CalendarDisruptorHeuristics.embeddingMatchConfidence)
    }

    @Test func notesAreSearchableForPhraseMatch() async {
        let ref = referenceDate()
        let events = [event(title: "Dinner", hour: 20, dayOffset: -1, notes: "Wine tasting downtown")]
        let candidate = await CalendarDisruptorClassifier.classify(
            events: events,
            userPhrases: [],
            metricSnapshots: [],
            referenceDate: ref,
            calendar: calendar
        )
        #expect(candidate?.tier == .userPhrase)
    }
}
