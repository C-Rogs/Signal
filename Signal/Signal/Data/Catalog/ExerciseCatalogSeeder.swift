import Foundation
import os
import SwiftData

@MainActor
enum ExerciseCatalogSeeder {
    private static let bundledResourceName = "free-exercise-db"
    private static let bundledResourceExtension = "json"

    static func seedIfNeeded(in context: ModelContext) throws -> Int {
        let existing = try context.fetchCount(FetchDescriptor<ExerciseCatalog>())
        if existing > 0 {
            Log.catalog.debug("catalog already seeded count=\(existing)")
            return existing
        }
        let records = try loadBundledRecords()
        var inserted = 0
        for record in records {
            let mapped = mapRecord(record)
            let entry = ExerciseCatalog(
                canonicalName: mapped.canonicalName,
                aliases: mapped.extraAliases,
                primaryMuscles: mapped.primary,
                secondaryMuscles: mapped.secondary,
                movementPattern: mapped.pattern,
                equipment: mapped.equipment,
                isUnilateral: mapped.isUnilateral,
                isCustom: false
            )
            context.insert(entry)
            inserted += 1
        }
        try context.save()
        Log.catalog.info("seeded exercise catalog count=\(inserted)")
        return inserted
    }

    static func loadBundledRecords() throws -> [FreeExerciseDBRecord] {
        guard let bundle = resourceBundle(),
              let url = bundle.url(
                  forResource: bundledResourceName,
                  withExtension: bundledResourceExtension
              )
        else {
            Log.catalog.error("missing bundled free-exercise-db.json")
            throw CatalogSeederError.missingBundledData
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([FreeExerciseDBRecord].self, from: data)
    }

    private static func mapRecord(_ record: FreeExerciseDBRecord) -> MappedRecord {
        let muscles = MuscleMapper.muscles(
            primary: record.primaryMuscles,
            secondary: record.secondaryMuscles,
            exerciseName: record.name
        )
        let equipment = ExerciseEquipmentMapper.map(
            datasetEquipment: record.equipment,
            exerciseName: record.name
        )
        let pattern = MovementPatternInferrer.infer(record: record)
        let isUnilateral = record.name.lowercased().contains("single")
            || record.name.lowercased().contains("one-arm")
            || record.name.lowercased().contains("one arm")
            || record.name.lowercased().contains("unilateral")
        var extraAliases: [String] = []
        if let hevy = CatalogAliasGenerator.hevyStyleTitle(
            canonicalName: record.name,
            equipment: equipment
        ) {
            extraAliases.append(hevy)
            extraAliases.append(contentsOf: CatalogAliasGenerator.simplifiedHevyAliases(from: hevy))
        }
        extraAliases.append(contentsOf: pluralVariants(of: record.name))
        if record.name == "Side Lateral Raise" {
            extraAliases.append("Lateral Raise (Dumbbell)")
        }
        return MappedRecord(
            canonicalName: record.name,
            extraAliases: extraAliases,
            primary: muscles.primary,
            secondary: muscles.secondary,
            pattern: pattern,
            equipment: equipment,
            isUnilateral: isUnilateral
        )
    }

    private static func pluralVariants(of name: String) -> [String] {
        var variants: [String] = []
        if name.hasSuffix("s"), name.count > 3 {
            variants.append(String(name.dropLast()))
        } else {
            variants.append(name + "s")
        }
        return variants
    }

    private struct MappedRecord {
        let canonicalName: String
        let extraAliases: [String]
        let primary: [Muscle]
        let secondary: [Muscle]
        let pattern: MovementPattern
        let equipment: ExerciseEquipment
        let isUnilateral: Bool
    }

    private static func resourceBundle() -> Bundle? {
        if Bundle.main.url(forResource: bundledResourceName, withExtension: bundledResourceExtension) != nil {
            return Bundle.main
        }
        return Bundle.allBundles.first { bundle in
            bundle.url(forResource: bundledResourceName, withExtension: bundledResourceExtension) != nil
        }
    }
}

enum CatalogSeederError: Error {
    case missingBundledData
}
