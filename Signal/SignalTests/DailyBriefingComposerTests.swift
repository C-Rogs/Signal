import Foundation
import Testing
@testable import Signal

struct DailyBriefingComposerTests {
    private func sampleScore(value: Double, classification: HRVBandClassification) -> RecoveryScore {
        RecoveryScore(
            value: value,
            hrvClassification: classification,
            hrvAnalysis: nil,
            rhrDelta: nil,
            sleepDelta: nil,
            confidence: .medium,
            breakdown: RecoveryScoreBreakdown(hrvTerm: 0, rhrTerm: 0, sleepTerm: 0, total: value),
            todayHRV: nil,
            todayRestingHR: nil
        )
    }

    @Test func composeUsesRecoverySummaryNotRawHRV() {
        let content = DailyBriefingComposer.compose(
            recoveryScore: sampleScore(value: 72, classification: .withinBand),
            insight: nil,
            flags: nil
        )
        #expect(content.body.contains("72/100"))
        #expect(!content.body.contains("ms"))
        #expect(content.body.contains("strong"))
    }

    @Test func composePrefersStrainHeadlineOverInsightWhenCaution() {
        let flags = ReadinessFlagsAssessment(
            signals: [
                ReadinessSignal(kind: .restingHRElevated, severity: .notice, coachingLine: "RHR up."),
                ReadinessSignal(kind: .hrvBelowBand, severity: .notice, coachingLine: "HRV down."),
            ],
            aggregateSeverity: .caution,
            headline: "Your body may need extra rest",
            detail: "Ease up today."
        )
        let content = DailyBriefingComposer.compose(
            recoveryScore: sampleScore(value: 40, classification: .belowLowerBand),
            insight: DailyBriefingInsightLine(
                bodyText: "Chest volume is low this week.",
                severity: .warning
            ),
            flags: flags
        )
        #expect(content.body.contains("Your body may need extra rest"))
        #expect(!content.body.contains("Chest volume"))
    }

    @Test func composeIncludesInsightWhenNoStrainFlags() {
        let content = DailyBriefingComposer.compose(
            recoveryScore: sampleScore(value: 55, classification: .withinBand),
            insight: DailyBriefingInsightLine(
                bodyText: "Training load is below your optimal zone.",
                severity: .warning
            ),
            flags: nil
        )
        #expect(content.body.contains("Training load is below"))
    }

    @Test func selectPriorityInsightPicksAlertOverWarning() {
        let chosen = DailyBriefingComposer.selectPriorityInsight(
            from: [
                DailyBriefingInsightLine(bodyText: "Warning line", severity: .warning),
                DailyBriefingInsightLine(bodyText: "Alert line", severity: .alert),
            ]
        )
        #expect(chosen?.bodyText == "Alert line")
    }
}
