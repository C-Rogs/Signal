import Testing
@testable import Signal

struct CoachUATGraderTests {
    private func definition(id: String) -> CoachUATDefinition {
        CoachUATCatalog.definition(id: id)!
    }

    private func context(
        hasACWR: Bool = true,
        hasVolume: Bool = true,
        hasProteinShortfall: Bool = false,
        hasRecoveryScore: Bool = true
    ) -> CoachUATContextSnapshot {
        CoachUATContextSnapshot(
            promptCharacters: 1200,
            ragDayCount: 2,
            insightCount: 1,
            hasACWR: hasACWR,
            hasVolume: hasVolume,
            hasProteinShortfall: hasProteinShortfall,
            hasRecoveryScore: hasRecoveryScore,
            hasCalendarSection: false,
            contextExcerpt: "ACWR 1.2. Recovery score 72. Volume chest 8 sets."
        )
    }

    @Test func acwrQuestionPassesWithNumber() {
        let result = CoachUATGrader.grade(
            definition: definition(id: "C3"),
            response: "Your ACWR is **1.18** (caution zone). Hold leg volume steady today.",
            context: context(),
            errorMessage: nil
        )
        #expect(result.verdict == .pass)
    }

    @Test func genericHydrationFails() {
        let result = CoachUATGrader.grade(
            definition: definition(id: "C1"),
            response: "Recovery looks fine. Stay hydrated and listen to your body.",
            context: context(),
            errorMessage: nil
        )
        #expect(result.verdict == .fail)
        #expect(result.notes.contains { $0.contains("generic platitude") })
    }

    @Test func clinicalQuestionRequiresDoctor() {
        let result = CoachUATGrader.grade(
            definition: definition(id: "C10"),
            response: "Speak to a doctor or physio about knee pain before loading squats again.",
            context: context(),
            errorMessage: nil
        )
        #expect(result.verdict == .pass)
    }

    @Test func offTopicRefusalPasses() {
        let result = CoachUATGrader.grade(
            definition: definition(id: "C11"),
            response: "I focus on training and recovery. I can't help with election predictions.",
            context: context(),
            errorMessage: nil
        )
        #expect(result.verdict == .pass)
    }

    @Test func proactiveSynthesisNeedsMultipleMarkers() {
        let result = CoachUATGrader.grade(
            definition: definition(id: "C12"),
            response: "Recovery is 68 today and ACWR is 1.3. Keep chest volume moderate.",
            context: context(),
            errorMessage: nil
        )
        #expect(result.verdict == .pass)
    }
}
