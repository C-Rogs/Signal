import Foundation
import Testing
@testable import Signal

struct WatchPayloadTests {
    @Test func scoreColorThresholds() {
        let high = WatchPayload(
            recoveryScore: 82,
            hrvClassification: HRVBandClassification.withinBand.rawValue,
            confidence: RecoveryConfidence.high.rawValue,
            todayHRV: 50,
            todayRestingHR: 58,
            lastUpdated: Date()
        )
        #expect(high.scoreColor == "Positive")

        let mid = WatchPayload(
            recoveryScore: 55,
            hrvClassification: HRVBandClassification.withinBand.rawValue,
            confidence: RecoveryConfidence.medium.rawValue,
            todayHRV: nil,
            todayRestingHR: nil,
            lastUpdated: Date()
        )
        #expect(mid.scoreColor == "Warning")

        let low = WatchPayload(
            recoveryScore: 25,
            hrvClassification: HRVBandClassification.belowLowerBand.rawValue,
            confidence: RecoveryConfidence.low.rawValue,
            todayHRV: nil,
            todayRestingHR: nil,
            lastUpdated: Date()
        )
        #expect(low.scoreColor == "Negative")
    }

    @Test func scoreColorBoundaryValues() {
        let atPositive = WatchPayload(
            recoveryScore: 70,
            hrvClassification: HRVBandClassification.withinBand.rawValue,
            confidence: RecoveryConfidence.high.rawValue,
            todayHRV: nil,
            todayRestingHR: nil,
            lastUpdated: Date()
        )
        #expect(atPositive.scoreColor == "Positive")

        let atWarning = WatchPayload(
            recoveryScore: 40,
            hrvClassification: HRVBandClassification.withinBand.rawValue,
            confidence: RecoveryConfidence.medium.rawValue,
            todayHRV: nil,
            todayRestingHR: nil,
            lastUpdated: Date()
        )
        #expect(atWarning.scoreColor == "Warning")
    }

    @Test func scoreIntRounding() {
        let lower = WatchPayload(
            recoveryScore: 82.4,
            hrvClassification: HRVBandClassification.withinBand.rawValue,
            confidence: RecoveryConfidence.high.rawValue,
            todayHRV: nil,
            todayRestingHR: nil,
            lastUpdated: Date()
        )
        #expect(lower.scoreInt == 82)

        let upper = WatchPayload(
            recoveryScore: 82.6,
            hrvClassification: HRVBandClassification.withinBand.rawValue,
            confidence: RecoveryConfidence.high.rawValue,
            todayHRV: nil,
            todayRestingHR: nil,
            lastUpdated: Date()
        )
        #expect(upper.scoreInt == 83)
    }

    @Test func jsonRoundTrip() throws {
        let original = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = WatchPayload(
            recoveryScore: 82,
            hrvClassification: HRVBandClassification.aboveUpperBand.rawValue,
            confidence: RecoveryConfidence.high.rawValue,
            todayHRV: 48.5,
            todayRestingHR: 57,
            lastUpdated: original
        )

        let data = try WatchPayload.makeEncoder().encode(payload)
        let decoded = try WatchPayload.makeDecoder().decode(WatchPayload.self, from: data)

        #expect(decoded == payload)
        #expect(abs(decoded.lastUpdated.timeIntervalSince(original)) < 1)
    }

    @Test func applicationContextRoundTripWithNilOptionals() throws {
        let original = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = WatchPayload(
            recoveryScore: 55,
            hrvClassification: HRVBandClassification.withinBand.rawValue,
            confidence: RecoveryConfidence.medium.rawValue,
            todayHRV: nil,
            todayRestingHR: nil,
            lastUpdated: original
        )

        let context = try payload.encodeToApplicationContext()
        #expect(context["todayHRV"] == nil)
        #expect(context["todayRestingHR"] == nil)

        let decoded = try WatchPayload.decode(from: context)
        #expect(decoded == payload)
    }
}
