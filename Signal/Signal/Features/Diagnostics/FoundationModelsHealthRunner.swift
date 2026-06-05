import Foundation
import FoundationModels
import os
import SwiftData

enum FoundationModelsHealthRunner {
    static func run(
        modelContainer: ModelContainer,
        definitions: [FoundationModelsHealthProbeDefinition] = FoundationModelsHealthCatalog.all,
        onProbeStart: (@Sendable (FoundationModelsHealthProbeDefinition) -> Void)? = nil,
        onProbeComplete: (@Sendable (FoundationModelsHealthProbeOutcome) -> Void)? = nil
    ) async -> FoundationModelsHealthReport {
        let modelStatus = CoachModelAvailabilityFormatter.currentStatus()
        var outcomes: [FoundationModelsHealthProbeOutcome] = []
        outcomes.reserveCapacity(definitions.count)

        var modelReady = modelStatus.canAskCoach

        for definition in definitions {
            onProbeStart?(definition)

            if !modelReady, definition.kind != .availability {
                let skipped = FoundationModelsHealthProbeOutcome(
                    probeID: definition.id,
                    label: definition.label,
                    verdict: .skip,
                    detail: "Skipped because model is not ready",
                    latencyMs: nil,
                    errorMessage: modelStatus.helpText
                )
                outcomes.append(skipped)
                onProbeComplete?(skipped)
                continue
            }

            let execution = await execute(
                definition: definition,
                modelContainer: modelContainer,
                modelStatus: modelStatus
            )
            let graded = FoundationModelsHealthGrader.grade(definition: definition, execution: execution)
            outcomes.append(graded)
            onProbeComplete?(graded)
            Log.coach.info(
                "fm_health_probe id=\(definition.id, privacy: .public) verdict=\(graded.verdict.rawValue, privacy: .public)"
            )

            if definition.kind == .availability {
                modelReady = modelStatus.canAskCoach
            }
        }

        let summaryLine = FoundationModelsHealthGrader.summarize(outcomes)
        let report = FoundationModelsHealthReport(
            generatedAt: Date(),
            modelStatusLabel: modelStatus.label,
            outcomes: outcomes,
            summaryLine: summaryLine
        )
        Log.coach.info("fm_health_report json=\(report.jsonString, privacy: .public)")
        return report
    }

    private static func execute(
        definition: FoundationModelsHealthProbeDefinition,
        modelContainer: ModelContainer,
        modelStatus: CoachModelAvailabilityFormatter.Status
    ) async -> FoundationModelsHealthProbeExecution {
        let started = Date()

        switch definition.kind {
        case .availability:
            return FoundationModelsHealthProbeExecution(
                boolValue: modelStatus.canAskCoach,
                detail: modelStatus.label,
                latencyMs: elapsedMs(since: started),
                errorMessage: modelStatus.canAskCoach ? nil : modelStatus.helpText
            )

        case .gateSerial:
            return await executeGateSerial(since: started)

        case .minimalGenerate:
            return await executeMinimalGenerate(since: started)

        case .structuredClassify(_, let eventTitle):
            return await executeStructuredClassify(eventTitle: eventTitle, since: started)

        case .coachStream:
            return await executeCoachStream(modelContainer: modelContainer, since: started)

        case .toolRoundtrip:
            return await executeToolRoundtrip(since: started)
        }
    }

    private static func executeGateSerial(since started: Date) async -> FoundationModelsHealthProbeExecution {
        let gate = FoundationModelsInferenceGate.shared
        let first = await gate.tryAcquire()
        let second = await gate.tryAcquire()
        if first {
            await gate.release()
        }
        return FoundationModelsHealthProbeExecution(
            boolValue: first,
            secondaryBoolValue: second,
            latencyMs: elapsedMs(since: started)
        )
    }

    private static func executeMinimalGenerate(since started: Date) async -> FoundationModelsHealthProbeExecution {
        do {
            guard let text = try await FoundationModelsInferenceGate.shared.withExclusiveAccess({
                try await Self.minimalGenerateText()
            }) else {
                return FoundationModelsHealthProbeExecution(
                    latencyMs: elapsedMs(since: started),
                    errorMessage: "Inference gate busy"
                )
            }
            return FoundationModelsHealthProbeExecution(
                textValue: text,
                latencyMs: elapsedMs(since: started)
            )
        } catch {
            return FoundationModelsHealthProbeExecution(
                latencyMs: elapsedMs(since: started),
                errorMessage: error.localizedDescription
            )
        }
    }

    private static func minimalGenerateText() async throws -> String {
        let session = LanguageModelSession(instructions: "Reply with one short word only.")
        guard !session.isResponding else {
            throw CoachError.busy
        }
        let stream = session.streamResponse(to: "Say hello.")
        var text = ""
        for try await snapshot in stream {
            text = snapshot.content
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func executeStructuredClassify(
        eventTitle: String,
        since started: Date
    ) async -> FoundationModelsHealthProbeExecution {
        let result = await CalendarAlcoholFMClassifier.classify(
            eventTitle: eventTitle,
            shortSleepLastNight: false
        )
        let alcoholLikely = result != nil
        return FoundationModelsHealthProbeExecution(
            boolValue: alcoholLikely,
            detail: result.map { "confidence=\($0.confidence) reason=\($0.reason)" },
            latencyMs: elapsedMs(since: started)
        )
    }

    private static func executeCoachStream(
        modelContainer: ModelContainer,
        since started: Date
    ) async -> FoundationModelsHealthProbeExecution {
        _ = modelContainer
        let context = FoundationModelsHealthFixtures.minimalCoachContext
        let query = "Reply with one short sentence confirming you can read this health check."
        var working = context
        working.prepareForModelInput(query: query)
        let prompt = working.assembledPrompt(query: query)

        do {
            guard let combined = try await FoundationModelsInferenceGate.shared.withExclusiveAccess({
                try await Self.streamCoachSmoke(prompt: prompt)
            }) else {
                return FoundationModelsHealthProbeExecution(
                    latencyMs: elapsedMs(since: started),
                    errorMessage: "Inference gate busy"
                )
            }
            return FoundationModelsHealthProbeExecution(
                textValue: combined,
                latencyMs: elapsedMs(since: started)
            )
        } catch {
            return FoundationModelsHealthProbeExecution(
                latencyMs: elapsedMs(since: started),
                errorMessage: error.localizedDescription
            )
        }
    }

    private static func streamCoachSmoke(prompt: String) async throws -> String {
        let session = LanguageModelSession(
            model: .default,
            tools: [DeviceClockTool()],
            instructions: "You are Signal coach. Answer briefly using only the user context below."
        )
        guard !session.isResponding else {
            throw CoachError.busy
        }
        let stream = session.streamResponse(to: prompt)
        var combined = ""
        for try await snapshot in stream {
            combined = snapshot.content
        }
        return combined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func executeToolRoundtrip(since started: Date) async -> FoundationModelsHealthProbeExecution {
        do {
            guard let text = try await FoundationModelsInferenceGate.shared.withExclusiveAccess({
                try await Self.toolRoundtripText()
            }) else {
                return FoundationModelsHealthProbeExecution(
                    latencyMs: elapsedMs(since: started),
                    errorMessage: "Inference gate busy"
                )
            }
            return FoundationModelsHealthProbeExecution(
                textValue: text,
                latencyMs: elapsedMs(since: started)
            )
        } catch {
            return FoundationModelsHealthProbeExecution(
                latencyMs: elapsedMs(since: started),
                errorMessage: error.localizedDescription
            )
        }
    }

    private static func toolRoundtripText() async throws -> String {
        let session = LanguageModelSession(
            model: .default,
            tools: [DeviceClockTool()],
            instructions: "When asked for the device clock, call getDeviceClock and return that value."
        )
        guard !session.isResponding else {
            throw CoachError.busy
        }
        let stream = session.streamResponse(to: "What is the device clock right now?")
        var text = ""
        for try await snapshot in stream {
            text = snapshot.content
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func elapsedMs(since started: Date) -> Int {
        Int(Date().timeIntervalSince(started) * 1000)
    }
}

enum FoundationModelsHealthFixtures {
    static let minimalCoachContext = CoachContext(
        userSummary: "Health check user",
        activeInsights: [],
        derivedMetricsSummary: "ACWR 1.0",
        personalReadinessSummary: "Readiness stable",
        ragSummaries: [],
        recentWorkouts: ["2026-06-01 Squat 3x5"],
        calendarSummary: ""
    )
}
