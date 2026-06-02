import Foundation
import Testing
@testable import Signal

struct TemporalQueryParserTests {
    @Test func lastWeekWindowEndsOnReferenceDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 2))
        )

        let window = TemporalQueryParser.window(
            in: "how did I sleep last week",
            referenceDate: reference,
            calendar: calendar
        )

        #expect(window != nil)
        #expect(window?.toDayKey == "2026-06-02")
        #expect(window?.fromDayKey == "2026-05-27")
        #expect(window?.contains(dayKey: "2024-08-12") == false)
        #expect(window?.contains(dayKey: "2026-05-30") == true)
    }

    @Test func retrievalFilterPrefersInWindowNeighbors() {
        let neighbors = [
            VectorNeighbor(dayKey: "2024-03-01", summaryText: "old sleep", similarity: 0.92),
            VectorNeighbor(dayKey: "2026-05-30", summaryText: "recent sleep", similarity: 0.81),
            VectorNeighbor(dayKey: "2026-06-01", summaryText: "recent sleep 2", similarity: 0.79),
        ]
        let window = TemporalQueryWindow(
            fromDayKey: "2026-05-27",
            toDayKey: "2026-06-02",
            label: "last 7 days"
        )

        let filtered = DiagnosticsRetrieval.rankedNeighbors(
            neighbors,
            temporalWindow: window,
            recencyIntent: false,
            topK: 2
        )

        #expect(filtered.neighbors.count == 2)
        #expect(filtered.neighbors.allSatisfy { window.contains(dayKey: $0.dayKey) })
        #expect(filtered.neighbors.first?.dayKey == "2026-05-30")
        #expect(filtered.usedTemporalFilter == true)
        #expect(filtered.usedRecencyRanking == false)
        #expect(filtered.fallbackToGlobal == false)
        #expect(filtered.footnote == "Filtered to last 7 days.")
    }

    @Test func recencyIntentDoesNotOverlapFixedWindow() {
        #expect(TemporalQueryParser.hasRecencyIntent(in: "when was my last leg day"))
        #expect(TemporalQueryParser.hasRecencyIntent(in: "hard leg days") == false)
        #expect(TemporalQueryParser.hasRecencyIntent(in: "how did I sleep last week") == false)
        #expect(TemporalQueryParser.hasRecencyIntent(in: "sleep in last 7 days") == false)
        #expect(TemporalQueryParser.hasRecencyIntent(in: "sleep in the last 7 days") == false)
    }

    @Test func sleepInTheLastSevenDaysUsesFixedWindowNotRecency() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 2))
        )

        let mode = QueryRetrievalMode.resolve(
            in: "sleep in the last 7 days",
            referenceDate: reference,
            calendar: calendar
        )

        guard case .fixedWindow(let window) = mode else {
            Issue.record("Expected fixed window, got \(mode)")
            return
        }
        #expect(window.label == "last 7 days")
    }

    @Test func recencyRankingPrefersNewestAmongSemanticAndRecentPool() {
        let neighbors = (0 ..< 50).map { index in
            VectorNeighbor(
                dayKey: String(format: "2024-%02d-01", (index % 12) + 1),
                summaryText: "Sleep",
                similarity: 0.99 - Float(index) * 0.01
            )
        } + [
            VectorNeighbor(dayKey: "2026-06-01", summaryText: "Sleep", similarity: 0.20),
        ]

        let outcome = DiagnosticsRetrieval.rankedNeighbors(
            neighbors,
            temporalWindow: nil,
            recencyIntent: true,
            topK: 1
        )

        #expect(outcome.footnote == "Most recent matches")
        #expect(outcome.neighbors.first?.dayKey == "2026-06-01")
    }

    @Test func recencyRankingPicksNewestAmongSemanticPool() {
        let neighbors = [
            VectorNeighbor(dayKey: "2024-01-01", summaryText: "leg day", similarity: 0.95),
            VectorNeighbor(dayKey: "2026-03-15", summaryText: "leg day", similarity: 0.80),
            VectorNeighbor(dayKey: "2025-06-01", summaryText: "leg day", similarity: 0.85),
        ]

        let outcome = DiagnosticsRetrieval.rankedNeighbors(
            neighbors,
            temporalWindow: nil,
            recencyIntent: true,
            topK: 1
        )

        #expect(outcome.neighbors.first?.dayKey == "2026-03-15")
        #expect(outcome.usedRecencyRanking == true)
        #expect(outcome.footnote == "Most recent matches")
    }

    @Test func fixedWindowPhraseCoverage() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 2))
        )

        let phrases = [
            "sleep in last 7 days",
            "sleep in the last 7 days",
            "how did I sleep last week",
            "last 7 days",
            "past week",
            "this week",
        ]

        for phrase in phrases {
            let window = TemporalQueryParser.window(
                in: phrase,
                referenceDate: reference,
                calendar: calendar
            )
            #expect(window != nil, "Expected fixed window for: \(phrase)")
        }
    }

    @Test func rollingSevenDayPhrasesShareSameWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 2))
        )

        let phrases = [
            "sleep in last 7 days",
            "sleep in the last 7 days",
            "how did I sleep last week",
            "last 7 days",
            "past week",
        ]

        let expectedFrom = "2026-05-27"
        let expectedTo = "2026-06-02"

        for phrase in phrases {
            let window = try #require(
                TemporalQueryParser.window(
                    in: phrase,
                    referenceDate: reference,
                    calendar: calendar
                )
            )
            #expect(window.fromDayKey == expectedFrom, "fromDayKey for: \(phrase)")
            #expect(window.toDayKey == expectedTo, "toDayKey for: \(phrase)")
            #expect(window.label == "last 7 days")
        }
    }

    @Test func sleepInLastSevenDaysRetrieverExcludesHistoricalDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 2))
        )

        let query = "sleep in last 7 days"
        let window = try #require(
            TemporalQueryParser.window(in: query, referenceDate: reference, calendar: calendar)
        )
        #expect(TemporalQueryParser.hasRecencyIntent(in: query, referenceDate: reference, calendar: calendar) == false)

        let neighbors = [
            VectorNeighbor(dayKey: "2024-06-01", summaryText: "Sleep 8.0 hours.", similarity: 0.99),
            VectorNeighbor(dayKey: "2025-06-01", summaryText: "Sleep 7.5 hours.", similarity: 0.97),
            VectorNeighbor(dayKey: "2026-05-28", summaryText: "Sleep 7.0 hours.", similarity: 0.75),
            VectorNeighbor(dayKey: "2026-06-01", summaryText: "Sleep 6.5 hours.", similarity: 0.70),
        ]

        let outcome = DiagnosticsRetrieval.rankedNeighbors(
            neighbors,
            temporalWindow: window,
            recencyIntent: false,
            topK: 8
        )

        #expect(outcome.usedTemporalFilter == true)
        #expect(outcome.fallbackToGlobal == false)
        #expect(outcome.footnote == "Filtered to last 7 days.")
        #expect(outcome.neighbors.allSatisfy { window.contains(dayKey: $0.dayKey) })
        #expect(outcome.neighbors.contains { $0.dayKey == "2024-06-01" } == false)
        #expect(outcome.neighbors.contains { $0.dayKey == "2025-06-01" } == false)
        #expect(outcome.neighbors.map(\.dayKey).sorted() == ["2026-05-28", "2026-06-01"])
    }

    @Test func pureCosineKeepsSimilarityOrder() {
        let neighbors = [
            VectorNeighbor(dayKey: "2024-01-01", summaryText: "legs", similarity: 0.95),
            VectorNeighbor(dayKey: "2026-03-15", summaryText: "legs", similarity: 0.80),
        ]

        let outcome = DiagnosticsRetrieval.rankedNeighbors(
            neighbors,
            temporalWindow: nil,
            recencyIntent: false,
            topK: 2
        )

        #expect(outcome.neighbors.map(\.dayKey) == ["2024-01-01", "2026-03-15"])
        #expect(outcome.usedRecencyRanking == false)
        #expect(outcome.footnote == nil)
    }
}
