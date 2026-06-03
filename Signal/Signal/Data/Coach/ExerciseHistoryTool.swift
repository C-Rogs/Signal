import Foundation
import FoundationModels
import SwiftData

struct ExerciseHistoryTool: Tool {
    let modelContainer: ModelContainer

    let name = "exerciseHistory"
    let description = "Last 5 sessions for a named exercise with weight, reps, and e1RM."

    @Generable
    struct Arguments {
        @Guide(description: "Exercise name to look up")
        var exerciseName: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            Self.lookup(exerciseName: arguments.exerciseName, modelContainer: modelContainer)
        }
    }

    @MainActor
    private static func lookup(exerciseName: String, modelContainer: ModelContainer) -> String {
        let trimmed = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No history found for \(exerciseName)."
        }

        let context = ModelContext(modelContainer)
        let catalog = (try? context.fetch(FetchDescriptor<ExerciseCatalog>())) ?? []
        guard let match = bestCatalogMatch(for: trimmed, in: catalog) else {
            return "No history found for \(trimmed)."
        }

        let exerciseID = match.canonicalName
        let rows: [ExerciseProgress]
        do {
            rows = try ExerciseProgressStore.fetchHistory(exerciseID: exerciseID, in: context)
        } catch {
            return "No history found for \(trimmed)."
        }

        let recent = Array(rows.suffix(5))
        guard !recent.isEmpty else {
            return "No history found for \(trimmed)."
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let lines = recent.map { row in
            let date = formatter.string(from: row.sessionDate)
            let weight = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), row.bestSetWeight_kg)
            let e1rm = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), row.e1RM_kg)
            return "\(date): \(weight)kg × \(row.bestSetReps) reps (e1RM \(e1rm) kg)"
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    private static func bestCatalogMatch(for name: String, in catalog: [ExerciseCatalog]) -> ExerciseCatalog? {
        let needle = name.lowercased()
        if let exact = catalog.first(where: { $0.canonicalName.lowercased() == needle }) {
            return exact
        }
        return catalog.first { entry in
            if entry.canonicalName.lowercased().contains(needle) { return true }
            return entry.aliases.contains { $0.lowercased().contains(needle) || needle.contains($0.lowercased()) }
        }
    }
}
