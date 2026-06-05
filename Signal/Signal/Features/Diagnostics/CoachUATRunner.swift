import Foundation
import os
import SwiftData

struct CoachUATReport: Sendable, Equatable, Codable {
    let generatedAt: Date
    let modelStatusLabel: String
    let results: [CoachUATResult]
    let summaryLine: String

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}

enum CoachUATRunner {
    static func run(
        modelContainer: ModelContainer,
        definitions: [CoachUATDefinition] = CoachUATCatalog.all,
        policy: CoachUATRunPolicy = .full,
        onCaseStart: (@Sendable (CoachUATDefinition) -> Void)? = nil,
        onCaseComplete: (@Sendable (CoachUATResult) -> Void)? = nil
    ) async -> CoachUATReport {
        let modelStatus = CoachModelAvailabilityFormatter.currentStatus()
        guard modelStatus.canAskCoach else {
            let skipped = definitions.map { definition in
                CoachUATResult(
                    definitionID: definition.id,
                    label: definition.label,
                    query: definition.query,
                    category: definition.category,
                    verdict: .limit,
                    checkLabel: definition.checkLabel,
                    ratioLabel: "0/\(definition.gradeRules.count)",
                    responsePreview: "",
                    contextSnapshot: CoachUATContextSnapshot.empty,
                    notes: ["Apple Intelligence not ready"],
                    errorMessage: modelStatus.helpText,
                    latencyMs: nil
                )
            }
            return makeReport(modelStatusLabel: modelStatus.label, results: skipped)
        }

        let coach = FoundationModelsCoach(modelContainer: modelContainer)
        let contextBuilder = CoachContextBuilder()
        var results: [CoachUATResult] = []
        results.reserveCapacity(definitions.count)

        for (index, definition) in definitions.enumerated() {
            if index > 0, policy.interCaseDelaySeconds > 0 {
                try? await Task.sleep(nanoseconds: policy.interCaseDelaySeconds * 1_000_000_000)
            }
            onCaseStart?(definition)
            let result = await runCase(
                definition: definition,
                coach: coach,
                contextBuilder: contextBuilder,
                modelContainer: modelContainer,
                policy: policy
            )
            results.append(result)
            onCaseComplete?(result)
            Log.coach.info(
                "coach_uat id=\(definition.id, privacy: .public) verdict=\(result.verdict.rawValue, privacy: .public) ratio=\(result.ratioLabel, privacy: .public)"
            )
        }

        let report = makeReport(modelStatusLabel: modelStatus.label, results: results)
        Log.coach.info("coach_uat_report json=\(report.jsonString, privacy: .public)")
        return report
    }

    private static func runCase(
        definition: CoachUATDefinition,
        coach: FoundationModelsCoach,
        contextBuilder: CoachContextBuilder,
        modelContainer: ModelContainer,
        policy: CoachUATRunPolicy
    ) async -> CoachUATResult {
        let started = Date()
        let maxAttempts = max(1, policy.maxAttempts)

        for attempt in 1...maxAttempts {
            if attempt > 1, policy.retryBackoffSeconds > 0 {
                try? await Task.sleep(nanoseconds: policy.retryBackoffSeconds * 1_000_000_000)
            }
            await waitForCoachIdle(coach)

            do {
                let context = try await contextBuilder.buildContext(
                    for: definition.query,
                    modelContainer: modelContainer
                )
                let snapshot = snapshot(from: context, query: definition.query)
                let stream = try await coach.respond(to: definition.query, context: context)
                var response = ""
                for try await chunk in stream {
                    response += chunk
                }
                let graded = CoachUATGrader.grade(
                    definition: definition,
                    response: response,
                    context: snapshot,
                    errorMessage: nil
                )
                if graded.verdict == .fail,
                   attempt < maxAttempts,
                   policy.retryOnPlatitude,
                   shouldRetryGradedFailure(graded) {
                    continue
                }
                return CoachUATResult(
                    definitionID: graded.definitionID,
                    label: graded.label,
                    query: graded.query,
                    category: graded.category,
                    verdict: graded.verdict,
                    checkLabel: graded.checkLabel,
                    ratioLabel: graded.ratioLabel,
                    responsePreview: graded.responsePreview,
                    contextSnapshot: graded.contextSnapshot,
                    notes: graded.notes,
                    errorMessage: graded.errorMessage,
                    latencyMs: elapsedMs(since: started)
                )
            } catch {
                if attempt < maxAttempts, policy.retryOnTransientError, isTransientCoachError(error) {
                    continue
                }
                let graded = CoachUATGrader.grade(
                    definition: definition,
                    response: "",
                    context: .empty,
                    errorMessage: error.localizedDescription
                )
                return CoachUATResult(
                    definitionID: graded.definitionID,
                    label: graded.label,
                    query: graded.query,
                    category: graded.category,
                    verdict: graded.verdict,
                    checkLabel: graded.checkLabel,
                    ratioLabel: graded.ratioLabel,
                    responsePreview: graded.responsePreview,
                    contextSnapshot: graded.contextSnapshot,
                    notes: graded.notes,
                    errorMessage: graded.errorMessage,
                    latencyMs: elapsedMs(since: started)
                )
            }
        }

        let graded = CoachUATGrader.grade(
            definition: definition,
            response: "",
            context: .empty,
            errorMessage: "Coach UAT exhausted retries"
        )
        return CoachUATResult(
            definitionID: graded.definitionID,
            label: graded.label,
            query: graded.query,
            category: graded.category,
            verdict: graded.verdict,
            checkLabel: graded.checkLabel,
            ratioLabel: graded.ratioLabel,
            responsePreview: graded.responsePreview,
            contextSnapshot: graded.contextSnapshot,
            notes: graded.notes,
            errorMessage: graded.errorMessage,
            latencyMs: elapsedMs(since: started)
        )
    }

    private static func waitForCoachIdle(_ coach: FoundationModelsCoach) async {
        for _ in 0..<100 {
            if await !coach.isResponding { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private static func isTransientCoachError(_ error: Error) -> Bool {
        if case CoachError.busy = error { return true }
        if case CoachError.rateLimited = error { return true }
        if case CoachError.generationFailed = error {
            return error.localizedDescription.lowercased().contains("rate limit")
        }
        return error.localizedDescription.lowercased().contains("rate limit")
    }

    private static func shouldRetryGradedFailure(_ result: CoachUATResult) -> Bool {
        result.notes.contains { $0.contains("generic platitude") }
    }

    private static func makeReport(modelStatusLabel: String, results: [CoachUATResult]) -> CoachUATReport {
        CoachUATReport(
            generatedAt: Date(),
            modelStatusLabel: modelStatusLabel,
            results: results,
            summaryLine: CoachUATGrader.summarize(results)
        )
    }

    private static func snapshot(from context: CoachContext, query: String) -> CoachUATContextSnapshot {
        let prompt = context.assembledPrompt(query: query)
        let excerpt = String(prompt.prefix(1200))
        let metrics = context.derivedMetricsSummary.lowercased()
        let recovery = context.personalReadinessSummary.lowercased()
        return CoachUATContextSnapshot(
            promptCharacters: prompt.count,
            ragDayCount: context.ragSummaries.count,
            insightCount: context.activeInsights.count,
            hasACWR: metrics.contains("acwr"),
            hasVolume: metrics.contains("volume") || metrics.contains(" sets"),
            hasProteinShortfall: metrics.contains("below target") && metrics.contains("protein"),
            hasRecoveryScore: recovery.contains("recovery") || recovery.contains("readiness"),
            hasCalendarSection: !context.calendarSummary.isEmpty,
            contextExcerpt: excerpt
        )
    }

    private static func elapsedMs(since started: Date) -> Int {
        Int(Date().timeIntervalSince(started) * 1000)
    }
}

extension CoachUATContextSnapshot {
    static let empty = CoachUATContextSnapshot(
        promptCharacters: 0,
        ragDayCount: 0,
        insightCount: 0,
        hasACWR: false,
        hasVolume: false,
        hasProteinShortfall: false,
        hasRecoveryScore: false,
        hasCalendarSection: false,
        contextExcerpt: ""
    )
}
