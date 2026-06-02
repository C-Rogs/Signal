import Foundation
import os
import SwiftData

@MainActor
enum CatalogLinkService {
    static func linkAllWorkoutExercises(in context: ModelContext) throws -> CatalogMatchReport {
        _ = try ExerciseCatalogSeeder.seedIfNeeded(in: context)
        let catalog = try context.fetch(FetchDescriptor<ExerciseCatalog>())
        let exercises = try context.fetch(FetchDescriptor<WorkoutExercise>())
        let index = ExerciseCatalogMatcher.buildAliasIndex(catalog: catalog)

        for exercise in exercises {
            let result = ExerciseCatalogMatcher.match(
                importedTitle: exercise.exerciseTitle,
                catalog: catalog,
                aliasIndex: index
            )
            exercise.catalogEntry = result.entry
            exercise.catalogMatchFlag = result.flag.rawValue
        }
        try context.save()

        let titles = exercises.map(\.exerciseTitle)
        let report = CatalogMatchReporter.buildReport(for: titles, catalog: catalog)
        for line in report.matchTableLines {
            Log.catalog.info("\(line, privacy: .public)")
        }
        for line in report.reviewLines {
            Log.catalog.notice("\(line, privacy: .public)")
        }
        return report
    }

    static func linkExercise(_ exercise: WorkoutExercise, catalog: [ExerciseCatalog], aliasIndex: [String: ExerciseCatalog]) {
        let result = ExerciseCatalogMatcher.match(
            importedTitle: exercise.exerciseTitle,
            catalog: catalog,
            aliasIndex: aliasIndex
        )
        exercise.catalogEntry = result.entry
        exercise.catalogMatchFlag = result.flag.rawValue
    }
}
