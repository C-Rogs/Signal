import Foundation
import os
import SwiftData

@MainActor
enum ExerciseCatalogCurator {
    private static let targetDefaultCount = 220
    private static let maxPerMuscleEquipment = 4

    private static let stapleSubstrings: [String] = [
        "barbell bench press",
        "bench press",
        "incline bench press",
        "squat",
        "deadlift",
        "romanian deadlift",
        "overhead press",
        "shoulder press",
        "pull-up",
        "pull up",
        "chin-up",
        "lat pulldown",
        "barbell row",
        "dumbbell row",
        "leg press",
        "lunge",
        "hip thrust",
        "barbell curl",
        "dumbbell curl",
        "hammer curl",
        "tricep pushdown",
        "skull crusher",
        "calf raise",
        "plank",
        "crunch",
        "leg curl",
        "leg extension",
        "face pull",
        "lateral raise",
        "side lateral raise",
        "machine chest press",
        "machine bench press",
        "chest press",
        "tricep pushdown",
        "triceps pushdown",
        "cable triceps",
        "dumbbell bicep curl",
        "chest fly",
        "push-up",
        "dip",
        "farmer",
        "shrug",
        "good morning",
        "glute bridge",
        "running",
        "cycling",
        "rowing machine",
        "treadmill",
    ]

    static func applyPickerDefaultsIfNeeded(in context: ModelContext) throws {
        var descriptor = FetchDescriptor<ExerciseCatalog>(
            predicate: #Predicate { $0.isPickerDefault }
        )
        let existing = try context.fetchCount(descriptor)
        if existing > 0 {
            Log.catalog.debug("picker defaults already applied count=\(existing)")
            return
        }
        try applyPickerDefaults(in: context)
    }

    static func applyPickerDefaults(in context: ModelContext) throws {
        let catalog = try context.fetch(FetchDescriptor<ExerciseCatalog>())
        for entry in catalog {
            entry.isPickerDefault = false
        }

        var selected: Set<PersistentIdentifier> = []
        var bucketCounts: [String: Int] = [:]

        let scored = catalog.map { entry -> (ExerciseCatalog, Int) in
            (entry, score(entry))
        }.sorted { $0.1 > $1.1 }

        for (entry, scoreValue) in scored where scoreValue > 0 {
            guard selected.count < targetDefaultCount else { break }
            let bucketKey = bucketKey(for: entry)
            let count = bucketCounts[bucketKey, default: 0]
            guard count < maxPerMuscleEquipment else { continue }
            if isNearDuplicate(entry, among: catalog.filter { selected.contains($0.persistentModelID) }) {
                continue
            }
            selected.insert(entry.persistentModelID)
            bucketCounts[bucketKey] = count + 1
            entry.isPickerDefault = true
        }

        if selected.count < 120 {
            for entry in catalog where !selected.contains(entry.persistentModelID) {
                guard selected.count < targetDefaultCount else { break }
                guard entry.equipment != .other else { continue }
                let bucketKey = bucketKey(for: entry)
                let count = bucketCounts[bucketKey, default: 0]
                guard count < maxPerMuscleEquipment else { continue }
                selected.insert(entry.persistentModelID)
                bucketCounts[bucketKey] = count + 1
                entry.isPickerDefault = true
            }
        }

        try context.save()
        Log.catalog.info("applied picker defaults count=\(selected.count, privacy: .public)")
    }

    private static func score(_ entry: ExerciseCatalog) -> Int {
        let name = entry.canonicalName.lowercased()
        var value = 0
        if stapleSubstrings.contains(where: { name.contains($0) }) {
            value += 40
        }
        switch entry.equipment {
        case .barbell, .dumbbell, .machine, .cable, .bodyweight:
            value += 12
        case .kettlebell, .band, .smith:
            value += 6
        case .other:
            value += 0
        }
        if entry.movementPattern == .cardio {
            value += 8
        }
        if name.contains("variation") || name.contains("alternate") {
            value -= 20
        }
        if name.filter({ $0 == "(" }).count > 1 {
            value -= 8
        }
        return value
    }

    private static func bucketKey(for entry: ExerciseCatalog) -> String {
        let muscle = entry.primaryMuscles.first?.rawValue ?? "unknown"
        return "\(muscle)-\(entry.equipmentRaw)"
    }

    private static func normalizedName(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: "dumbbell", with: "")
            .replacingOccurrences(of: "barbell", with: "")
            .replacingOccurrences(of: "cable", with: "")
            .replacingOccurrences(of: "machine", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private static func isNearDuplicate(_ entry: ExerciseCatalog, among selected: [ExerciseCatalog]) -> Bool {
        let key = normalizedName(entry.canonicalName)
        return selected.contains { normalizedName($0.canonicalName) == key }
    }
}
