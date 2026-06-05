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

    @Test func recoveryWidgetSnapshotFromPayload() {
        let payload = WatchPayload(
            recoveryScore: 82,
            hrvClassification: HRVBandClassification.aboveUpperBand.rawValue,
            confidence: RecoveryConfidence.high.rawValue,
            todayHRV: 50,
            todayRestingHR: 58,
            lastUpdated: Date()
        )
        let snapshot = RecoveryWidgetSnapshot.make(from: payload)
        #expect(snapshot.scoreText == "82")
        #expect(snapshot.hrvLabel == "Above Baseline")
        #expect(snapshot.colorToken == "Positive")
        #expect(snapshot.scoreValue == 82)
        #expect(snapshot.gaugeProgress == 0.82)
    }

    @Test func complicationTimelinePolicyRefreshIntervals() {
        let now = Date(timeIntervalSince1970: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let waiting = WatchComplicationTimelinePolicy.nextReloadDate(
            after: now,
            isWaiting: true,
            calendar: calendar
        )
        #expect(waiting == now.addingTimeInterval(5 * 60))
        let active = WatchComplicationTimelinePolicy.nextReloadDate(
            after: now,
            isWaiting: false,
            calendar: calendar
        )
        #expect(active == now.addingTimeInterval(15 * 60))
    }

    @Test func bodyBatterySnapshotUsesPercentAndBatterySymbol() {
        let snapshot = RecoveryWidgetSnapshot.bodyBatteryPreview
        #expect(snapshot.bodyBatteryPercentText == "72%")
        #expect(snapshot.batterySymbolName == "battery.75percent")
    }

    @Test func recoveryWidgetSnapshotWaitingWhenNil() {
        let snapshot = RecoveryWidgetSnapshot.make(from: nil)
        #expect(snapshot == .waiting)
        #expect(snapshot.scoreText == "—")
        #expect(snapshot.hrvLabel == "Waiting")
        #expect(snapshot.scoreValue == nil)
        #expect(snapshot.gaugeProgress == 0)
    }

    @Test func recoveryWidgetSnapshotGaugeColorBoundariesMatchScoreToken() {
        let at70 = WatchPayload(
            recoveryScore: 70,
            hrvClassification: HRVBandClassification.withinBand.rawValue,
            confidence: RecoveryConfidence.high.rawValue,
            todayHRV: nil,
            todayRestingHR: nil,
            lastUpdated: Date()
        )
        #expect(RecoveryWidgetSnapshot.make(from: at70).colorToken == "Positive")
        #expect(RecoveryWidgetSnapshot.make(from: at70).gaugeProgress == 0.7)

        let at40 = WatchPayload(
            recoveryScore: 40,
            hrvClassification: HRVBandClassification.withinBand.rawValue,
            confidence: RecoveryConfidence.medium.rawValue,
            todayHRV: nil,
            todayRestingHR: nil,
            lastUpdated: Date()
        )
        #expect(RecoveryWidgetSnapshot.make(from: at40).colorToken == "Warning")

        let below40 = WatchPayload(
            recoveryScore: 39,
            hrvClassification: HRVBandClassification.belowLowerBand.rawValue,
            confidence: RecoveryConfidence.low.rawValue,
            todayHRV: nil,
            todayRestingHR: nil,
            lastUpdated: Date()
        )
        #expect(RecoveryWidgetSnapshot.make(from: below40).colorToken == "Negative")
    }

    @Test func recoveryWidgetSnapshotTimelineRefreshPolicy() {
        let payload = WatchPayload(
            recoveryScore: 55,
            hrvClassification: HRVBandClassification.withinBand.rawValue,
            confidence: RecoveryConfidence.medium.rawValue,
            todayHRV: nil,
            todayRestingHR: nil,
            lastUpdated: Date()
        )
        let snapshot = RecoveryWidgetSnapshot.make(from: payload)
        #expect(snapshot.scoreText == "55")
        #expect(snapshot.hrvLabel == "Within Range")
        #expect(snapshot.colorToken == "Warning")
        #expect(snapshot != .waiting)
    }

    @Test func scoreColorUsesPersonalBandsWhenCalibrated() {
        let payload = WatchPayload(
            recoveryScore: 52,
            hrvClassification: HRVBandClassification.withinBand.rawValue,
            confidence: RecoveryConfidence.high.rawValue,
            todayHRV: nil,
            todayRestingHR: nil,
            lastUpdated: Date(),
            personalP25: 45,
            personalP75: 55,
            isCalibrated: true
        )
        #expect(payload.scoreColor == "Warning")

        let aboveNorm = WatchPayload(
            recoveryScore: 58,
            hrvClassification: HRVBandClassification.withinBand.rawValue,
            confidence: RecoveryConfidence.high.rawValue,
            todayHRV: nil,
            todayRestingHR: nil,
            lastUpdated: Date(),
            personalP25: 45,
            personalP75: 55,
            isCalibrated: true
        )
        #expect(aboveNorm.scoreColor == "Positive")
    }

    @Test func decodeBackwardCompatibleWithoutPersonalBands() throws {
        let original = Date(timeIntervalSince1970: 1_700_000_000)
        let context: [String: Any] = [
            "recoveryScore": 55.0,
            "hrvClassification": HRVBandClassification.withinBand.rawValue,
            "confidence": RecoveryConfidence.medium.rawValue,
            "lastUpdated": ISO8601DateFormatter().string(from: original),
        ]
        let decoded = try WatchPayload.decode(from: context)
        #expect(decoded.personalP25 == nil)
        #expect(decoded.isCalibrated == nil)
        #expect(decoded.scoreColor == "Warning")
    }

    @Test func watchPayloadHRVBandDisplayLabel() {
        let below = WatchPayload(
            recoveryScore: 30,
            hrvClassification: HRVBandClassification.belowLowerBand.rawValue,
            confidence: RecoveryConfidence.low.rawValue,
            todayHRV: nil,
            todayRestingHR: nil,
            lastUpdated: Date()
        )
        #expect(below.hrvBandDisplayLabel == "Below Baseline")
    }
}
