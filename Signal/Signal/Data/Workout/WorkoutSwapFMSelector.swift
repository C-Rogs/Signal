import Foundation
import FoundationModels
import os
import SwiftData

struct WorkoutSwapSuggestion {
    let substitute: ExerciseCatalog
    let rationale: String
    let usedFoundationModel: Bool
}

enum WorkoutSwapError: Error, LocalizedError {
    case noCandidates

    var errorDescription: String? {
        switch self {
        case .noCandidates:
            return "No substitute exercises matched this movement."
        }
    }
}

@MainActor
enum WorkoutSwapOrchestrator {
    static func buildSuggestion(
        exercise: WorkoutExercise,
        constraint: String,
        recoveryScore: RecoveryScore?,
        personalReadiness: PersonalReadinessProfile?,
        deloadActive: Bool,
        in context: ModelContext
    ) async throws -> (WorkoutSwapSuggestion, SwapSetPlan) {
        let catalog = try context.fetch(FetchDescriptor<ExerciseCatalog>())
        let candidates = ExerciseSwapCandidateRanker.rank(
            source: exercise,
            constraint: constraint,
            catalog: catalog,
            in: context
        )
        guard !candidates.isEmpty else { throw WorkoutSwapError.noCandidates }

        let recoveryChip = recoveryScore.flatMap { LiveLoadCueEvaluator.sessionRecoveryChipTitle(for: $0) }
        guard let suggestion = await WorkoutSwapFMSelector.suggest(
            source: exercise,
            constraint: constraint,
            candidates: candidates,
            recoveryChip: recoveryChip
        ) else {
            throw WorkoutSwapError.noCandidates
        }

        let plan = try ExerciseSwapLoadPrescription.build(
            source: exercise,
            substitute: suggestion.substitute,
            recoveryScore: recoveryScore,
            personalReadiness: personalReadiness,
            deloadActive: deloadActive,
            in: context
        )
        return (suggestion, plan)
    }

    static func buildPlan(
        exercise: WorkoutExercise,
        substitute: ExerciseCatalog,
        recoveryScore: RecoveryScore?,
        personalReadiness: PersonalReadinessProfile?,
        deloadActive: Bool,
        in context: ModelContext
    ) throws -> SwapSetPlan {
        try ExerciseSwapLoadPrescription.build(
            source: exercise,
            substitute: substitute,
            recoveryScore: recoveryScore,
            personalReadiness: personalReadiness,
            deloadActive: deloadActive,
            in: context
        )
    }

    static func completedWorkingSetCount(for exercise: WorkoutExercise) -> Int {
        exercise.sets.filter {
            $0.isCompleted && WorkoutSetType(storageValue: $0.setType) != .warmup
        }.count
    }
}

enum WorkoutSwapFMSelector {
    @Generable
    struct ExerciseSwapSelection {
        @Guide(description: "Canonical exercise name; must be one of the candidate list")
        var substituteCanonicalName: String

        @Guide(description: "One sentence why this swap fits the constraint")
        var rationale: String
    }

    static func suggest(
        source: WorkoutExercise,
        constraint: String,
        candidates: [ExerciseSwapCandidate],
        recoveryChip: String?
    ) async -> WorkoutSwapSuggestion? {
        guard let first = candidates.first else { return nil }
        let candidateEntries = candidates.map(\.catalogEntry)

        guard CoachModelAvailabilityFormatter.currentStatus().canAskCoach else {
            return WorkoutSwapSuggestion(
                substitute: first.catalogEntry,
                rationale: fallbackRationale(for: first.catalogEntry, constraint: constraint),
                usedFoundationModel: false
            )
        }

        guard let selectionWrapper = await FoundationModelsInferenceGate.shared.withExclusiveAccess({
            await selectWithSession(
                source: source,
                constraint: constraint,
                candidates: candidateEntries,
                recoveryChip: recoveryChip
            )
        }), let selection = selectionWrapper else {
            return WorkoutSwapSuggestion(
                substitute: first.catalogEntry,
                rationale: fallbackRationale(for: first.catalogEntry, constraint: constraint),
                usedFoundationModel: false
            )
        }

        let names = Set(candidateEntries.map(\.canonicalName))
        if let match = candidateEntries.first(where: { $0.canonicalName == selection.substituteCanonicalName }),
           names.contains(selection.substituteCanonicalName)
        {
            return WorkoutSwapSuggestion(
                substitute: match,
                rationale: selection.rationale,
                usedFoundationModel: true
            )
        }

        Log.workout.info(
            "workout swap FM pick invalid name=\(selection.substituteCanonicalName, privacy: .public)"
        )
        return WorkoutSwapSuggestion(
            substitute: first.catalogEntry,
            rationale: fallbackRationale(for: first.catalogEntry, constraint: constraint),
            usedFoundationModel: false
        )
    }

    private static func selectWithSession(
        source: WorkoutExercise,
        constraint: String,
        candidates: [ExerciseCatalog],
        recoveryChip: String?
    ) async -> ExerciseSwapSelection? {
        let instructions = """
            You pick a substitute strength exercise from the numbered candidate list only.
            Never invent an exercise name outside the list.
            Prefer equipment that avoids the user's constraint.
            """

        let sourceSummary = sourceContextLine(for: source)
        let plannedSummary = plannedSetsSummary(for: source)
        let candidateLines = candidates.enumerated().map { index, entry in
            "\(index + 1). \(entry.canonicalName) (\(entry.equipment.rawValue))"
        }.joined(separator: "\n")

        var promptParts = [
            "Source exercise: \(sourceSummary)",
            "Planned sets: \(plannedSummary)",
            "User constraint: \(constraint.isEmpty ? "Need an alternative." : constraint)",
            "Candidates:\n\(candidateLines)",
        ]
        if let recoveryChip, !recoveryChip.isEmpty {
            promptParts.append("Recovery note: \(recoveryChip)")
        }
        let prompt = promptParts.joined(separator: "\n")

        do {
            let session = LanguageModelSession(instructions: instructions)
            guard !session.isResponding else {
                Log.workout.info("workout swap FM skipped session busy")
                return nil
            }
            let response = try await session.respond(
                to: prompt,
                generating: ExerciseSwapSelection.self
            )
            return response.content
        } catch {
            Log.workout.error("workout swap FM failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func sourceContextLine(for source: WorkoutExercise) -> String {
        if let catalog = source.catalogEntry {
            let muscles = catalog.primaryMuscles.map(\.rawValue).joined(separator: ", ")
            return "\(catalog.canonicalName); pattern \(catalog.movementPattern.rawValue); muscles \(muscles); equipment \(catalog.equipment.rawValue)"
        }
        return source.exerciseTitle
    }

    private static func plannedSetsSummary(for source: WorkoutExercise) -> String {
        let sets = source.sets.sorted { $0.setIndex < $1.setIndex }.filter { !$0.isCompleted }
        guard !sets.isEmpty else { return "none remaining" }
        return sets.prefix(4).map { set in
            let type = WorkoutSetType(storageValue: set.setType) == .warmup ? "warmup" : "working"
            let weight = set.weightKg.map { String(format: "%.1f kg", $0) } ?? "—"
            let reps = set.reps.map(String.init) ?? "—"
            return "\(type) \(weight) x \(reps)"
        }.joined(separator: "; ")
    }

    private static func fallbackRationale(for substitute: ExerciseCatalog, constraint: String) -> String {
        if constraint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(substitute.canonicalName) targets the same movement with \(substitute.equipment.rawValue) equipment."
        }
        return "\(substitute.canonicalName) avoids your constraint while keeping the same movement pattern."
    }
}
