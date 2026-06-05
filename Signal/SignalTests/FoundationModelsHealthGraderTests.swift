import Testing
@testable import Signal

struct FoundationModelsHealthGraderTests {
    @Test func availabilityPassWhenReady() {
        let definition = FoundationModelsHealthCatalog.definition(id: "model_ready")!
        let execution = FoundationModelsHealthProbeExecution(boolValue: true, detail: "Available")
        let outcome = FoundationModelsHealthGrader.grade(definition: definition, execution: execution)
        #expect(outcome.verdict == .pass)
    }

    @Test func availabilitySkipWhenNotReady() {
        let definition = FoundationModelsHealthCatalog.definition(id: "model_ready")!
        let execution = FoundationModelsHealthProbeExecution(
            boolValue: false,
            detail: "Downloading or not ready",
            errorMessage: "Model not ready"
        )
        let outcome = FoundationModelsHealthGrader.grade(definition: definition, execution: execution)
        #expect(outcome.verdict == .skip)
    }

    @Test func minimalGenerateFailsOnEmpty() {
        let definition = FoundationModelsHealthCatalog.definition(id: "minimal_text")!
        let execution = FoundationModelsHealthProbeExecution(textValue: "")
        let outcome = FoundationModelsHealthGrader.grade(definition: definition, execution: execution)
        #expect(outcome.verdict == .fail)
    }

    @Test func structuredPubNightReviewWhenNotLikely() {
        let definition = FoundationModelsHealthCatalog.definition(id: "structured_pub_night")!
        let execution = FoundationModelsHealthProbeExecution(boolValue: false)
        let outcome = FoundationModelsHealthGrader.grade(definition: definition, execution: execution)
        #expect(outcome.verdict == .review)
    }

    @Test func structuredDentistFailsWhenLikely() {
        let definition = FoundationModelsHealthCatalog.definition(id: "structured_dentist")!
        let execution = FoundationModelsHealthProbeExecution(boolValue: true)
        let outcome = FoundationModelsHealthGrader.grade(definition: definition, execution: execution)
        #expect(outcome.verdict == .fail)
    }

    @Test func gateSerialPassWhenSecondAcquireBlocked() {
        let definition = FoundationModelsHealthCatalog.definition(id: "gate_serial")!
        let execution = FoundationModelsHealthProbeExecution(boolValue: true, secondaryBoolValue: false)
        let outcome = FoundationModelsHealthGrader.grade(definition: definition, execution: execution)
        #expect(outcome.verdict == .pass)
    }

    @Test func coachStreamReviewOnShortReply() {
        let definition = FoundationModelsHealthCatalog.definition(id: "coach_stream")!
        let execution = FoundationModelsHealthProbeExecution(textValue: "OK")
        let outcome = FoundationModelsHealthGrader.grade(definition: definition, execution: execution)
        #expect(outcome.verdict == .review)
    }

    @Test func summarizeCountsVerdicts() {
        let outcomes = [
            FoundationModelsHealthProbeOutcome(
                probeID: "a",
                label: "A",
                verdict: .pass,
                detail: nil,
                latencyMs: nil,
                errorMessage: nil
            ),
            FoundationModelsHealthProbeOutcome(
                probeID: "b",
                label: "B",
                verdict: .review,
                detail: nil,
                latencyMs: nil,
                errorMessage: nil
            ),
        ]
        let summary = FoundationModelsHealthGrader.summarize(outcomes)
        #expect(summary == "1 PASS, 0 FAIL, 1 REVIEW, 0 SKIP")
        #expect(FoundationModelsHealthGrader.suitePassed(outcomes))
    }
}
