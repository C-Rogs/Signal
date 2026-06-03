import Foundation
import SwiftData
import Testing
@testable import Signal

@MainActor
struct SetHeartRateDataTests {
    @Test func fetchBySessionIDReturnsOnlyMatchingRows() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let sessionA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let sessionB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let setOne = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let setTwo = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        context.insert(
            SetHeartRateData(
                setEntryID: setOne,
                sessionID: sessionA,
                avgBPM: 120,
                maxBPM: 130,
                minBPM: 110,
                sampleCount: 4,
                windowStart: .now,
                windowEnd: .now
            )
        )
        context.insert(
            SetHeartRateData(
                setEntryID: setTwo,
                sessionID: sessionB,
                avgBPM: 100,
                maxBPM: 105,
                minBPM: 95,
                sampleCount: 3,
                windowStart: .now,
                windowEnd: .now
            )
        )
        try context.save()

        let rows = try SetHeartRateDataStore.fetch(sessionID: sessionA, in: context)
        #expect(rows.count == 1)
        #expect(rows[0].setEntryID == setOne)
        #expect(rows[0].sessionID == sessionA)
    }
}
