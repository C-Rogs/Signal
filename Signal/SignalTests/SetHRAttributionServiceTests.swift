import Foundation
import SwiftData
import Testing
@testable import Signal

struct SetHRAttributionServiceTests {
    private let sessionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let setA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let setB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    @Test func fiveSamplesInWindowComputesStats() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(60)
        let samples = stride(from: 0, to: 5, by: 1).map { index in
            HeartRateSamplePoint(
                timestamp: start.addingTimeInterval(Double(index) * 10),
                bpm: Double(100 + index * 10)
            )
        }
        let drafts = SetHRAttributionMath.computeDrafts(
            sessionID: sessionID,
            sets: [
                SetHRAttributionSetInput(
                    entryID: setA,
                    setIndex: 0,
                    isWarmup: false,
                    startedAt: start,
                    completedAt: end
                ),
            ],
            samples: samples
        )
        #expect(drafts.count == 1)
        let row = drafts[0]
        #expect(row.avgBPM == 120)
        #expect(row.maxBPM == 140)
        #expect(row.minBPM == 100)
        #expect(row.sampleCount == 5)
        #expect(!row.isRestInterval)
    }

    @Test func twoSamplesSkipped() {
        let start = Date(timeIntervalSince1970: 2_000)
        let end = start.addingTimeInterval(30)
        let samples = [
            HeartRateSamplePoint(timestamp: start, bpm: 110),
            HeartRateSamplePoint(timestamp: start.addingTimeInterval(10), bpm: 115),
        ]
        let drafts = SetHRAttributionMath.computeDrafts(
            sessionID: sessionID,
            sets: [
                SetHRAttributionSetInput(
                    entryID: setA,
                    setIndex: 0,
                    isWarmup: false,
                    startedAt: start,
                    completedAt: end
                ),
            ],
            samples: samples
        )
        #expect(drafts.isEmpty)
    }

    @Test func nilStartedAtSkipped() {
        let drafts = SetHRAttributionMath.computeDrafts(
            sessionID: sessionID,
            sets: [
                SetHRAttributionSetInput(
                    entryID: setA,
                    setIndex: 0,
                    isWarmup: false,
                    startedAt: nil,
                    completedAt: Date(timeIntervalSince1970: 3_000)
                ),
            ],
            samples: [
                HeartRateSamplePoint(timestamp: Date(timeIntervalSince1970: 3_000), bpm: 120),
            ]
        )
        #expect(drafts.isEmpty)
    }

    @MainActor
    @Test func upsertDoesNotDuplicateRows() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let draft = SetHeartRateDataDraft(
            setEntryID: setA,
            sessionID: sessionID,
            avgBPM: 130,
            maxBPM: 140,
            minBPM: 120,
            sampleCount: 4,
            windowStart: Date(timeIntervalSince1970: 4_000),
            windowEnd: Date(timeIntervalSince1970: 4_060),
            isRestInterval: false
        )
        try SetHeartRateDataStore.upsert([draft], in: context)
        try SetHeartRateDataStore.upsert(
            [
                SetHeartRateDataDraft(
                    setEntryID: setA,
                    sessionID: sessionID,
                    avgBPM: 135,
                    maxBPM: 145,
                    minBPM: 125,
                    sampleCount: 5,
                    windowStart: draft.windowStart,
                    windowEnd: draft.windowEnd,
                    isRestInterval: false
                ),
            ],
            in: context
        )
        let count = try context.fetchCount(FetchDescriptor<SetHeartRateData>())
        #expect(count == 1)
        let stored = try SetHeartRateDataStore.fetch(setEntryID: setA, isRestInterval: false, in: context)
        #expect(stored?.avgBPM == 135)
    }

    @Test func restIntervalAttributedToNextSet() {
        let set0End = Date(timeIntervalSince1970: 5_000)
        let set1Start = set0End.addingTimeInterval(30)
        let set1End = set1Start.addingTimeInterval(45)
        let samples = [
            HeartRateSamplePoint(timestamp: set0End.addingTimeInterval(5), bpm: 130),
            HeartRateSamplePoint(timestamp: set0End.addingTimeInterval(15), bpm: 125),
            HeartRateSamplePoint(timestamp: set0End.addingTimeInterval(25), bpm: 118),
        ]
        let drafts = SetHRAttributionMath.computeDrafts(
            sessionID: sessionID,
            sets: [
                SetHRAttributionSetInput(
                    entryID: setA,
                    setIndex: 0,
                    isWarmup: false,
                    startedAt: set0End.addingTimeInterval(-40),
                    completedAt: set0End
                ),
                SetHRAttributionSetInput(
                    entryID: setB,
                    setIndex: 1,
                    isWarmup: false,
                    startedAt: set1Start,
                    completedAt: set1End
                ),
            ],
            samples: samples
        )
        let rest = drafts.first { $0.isRestInterval }
        #expect(rest != nil)
        #expect(rest?.setEntryID == setB)
        let expectedRestAvg = (130.0 + 125.0 + 118.0) / 3.0
        #expect(abs((rest?.avgBPM ?? 0) - expectedRestAvg) < 0.01)
    }

    @Test func noSamplesProducesNoRows() {
        let drafts = SetHRAttributionMath.computeDrafts(
            sessionID: sessionID,
            sets: [
                SetHRAttributionSetInput(
                    entryID: setA,
                    setIndex: 0,
                    isWarmup: false,
                    startedAt: Date(timeIntervalSince1970: 6_000),
                    completedAt: Date(timeIntervalSince1970: 6_100)
                ),
            ],
            samples: []
        )
        #expect(drafts.isEmpty)
    }
}
