import Foundation
import SwiftData
import Testing
@testable import Signal

@MainActor
struct ExerciseCatalogTests {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func representativeTitlesMatchCatalog() throws {
        let container = try seededContainer()
        let catalog = try fetchCatalog(in: container)
        let index = ExerciseCatalogMatcher.buildAliasIndex(catalog: catalog)

        let squat = ExerciseCatalogMatcher.match(importedTitle: "Squat (Barbell)", catalog: catalog, aliasIndex: index)
        #expect(squat.flag == .matched)
        #expect(squat.entry?.canonicalName.lowercased().contains("squat") == true)

        let bench = ExerciseCatalogMatcher.match(importedTitle: "Bench Press (Barbell)", catalog: catalog, aliasIndex: index)
        #expect(bench.flag == .matched)

        let deadlift = ExerciseCatalogMatcher.match(importedTitle: "Deadlift (Barbell)", catalog: catalog, aliasIndex: index)
        #expect(deadlift.flag == .matched)

        let pullUp = ExerciseCatalogMatcher.match(importedTitle: "Pull Up", catalog: catalog, aliasIndex: index)
        #expect(pullUp.flag == .matched)
        #expect(pullUp.entry?.primaryMuscles.contains(.lats) == true)
        #expect(pullUp.entry?.secondaryMuscles.contains(.biceps) == true)

        let lateral = ExerciseCatalogMatcher.match(importedTitle: "Lateral Raise (Dumbbell)", catalog: catalog, aliasIndex: index)
        #expect(lateral.flag == .matched)

        let machine = ExerciseCatalogMatcher.match(importedTitle: "Leg Extension (Machine)", catalog: catalog, aliasIndex: index)
        #expect(machine.flag == .matched)

        let run = ExerciseCatalogMatcher.match(importedTitle: "Running", catalog: catalog, aliasIndex: index)
        #expect(run.flag == .matched)
        #expect(run.entry?.movementPattern == .cardio)
    }

    @Test func fractionalVolumePullUpCountsLatsAndBiceps() throws {
        let container = try seededContainer()
        let context = ModelContext(container)
        let catalog = try fetchCatalog(in: container)
        let index = ExerciseCatalogMatcher.buildAliasIndex(catalog: catalog)
        let match = ExerciseCatalogMatcher.match(importedTitle: "Pull Up", catalog: catalog, aliasIndex: index)
        #expect(match.entry != nil)

        let exercise = WorkoutExercise(exerciseTitle: "Pull Up", order: 0, catalogEntry: match.entry, catalogMatchFlag: CatalogMatchFlag.matched.rawValue)
        let set = SetEntry(setIndex: 0, setType: "normal", reps: 8)
        set.exercise = exercise
        exercise.sets = [set]

        let volume = FractionalVolume.fractionalVolume(for: set, exercise: exercise)
        #expect(volume[.lats] == 1.0)
        #expect(volume[.biceps] == 0.5)
    }

    @Test func legSessionOct2025HasQuadHamGluteVolume() throws {
        let container = try seededContainer()
        let context = ModelContext(container)
        let csvURL = Bundle(for: BundleToken.self).url(forResource: "HevyExport", withExtension: "csv", subdirectory: nil)
            ?? URL(fileURLWithPath: "/Users/cameronro/Development/Signal/fixtures/HevyExport.csv")
        let csvData = try Data(contentsOf: csvURL)
        let parsed = try HevyCSVParser.parse(data: csvData, calendar: Self.utcCalendar)
        _ = try WorkoutStore.upsert(
            parsedSessions: parsed.sessions,
            source: HevyCSVImporter.importSource,
            in: context
        )
        _ = try CatalogLinkService.linkAllWorkoutExercises(in: context)

        let legDay = Self.utcDay(2025, 10, 14)

        let volumes = try UserMuscleVolumeService.weeklyVolumePerMuscle(
            from: legDay,
            to: legDay,
            source: HevyCSVImporter.importSource,
            in: context,
            calendar: Self.utcCalendar
        )

        #expect((volumes[.quads] ?? 0) > 0)
        #expect((volumes[.hamstrings] ?? 0) > 0)
        #expect((volumes[.glutes] ?? 0) > 0)
    }

    @Test func unmatchedCustomTitleIsFlagged() throws {
        let container = try seededContainer()
        let context = ModelContext(container)
        let catalog = try fetchCatalog(in: container)
        let index = ExerciseCatalogMatcher.buildAliasIndex(catalog: catalog)

        let exercise = WorkoutExercise(exerciseTitle: "Camron Special Curl", order: 0)
        context.insert(exercise)
        CatalogLinkService.linkExercise(exercise, catalog: catalog, aliasIndex: index)

        #expect(exercise.catalogEntry == nil)
        #expect(exercise.catalogMatch == .unmatched)
    }

    @Test func geminiImportStapleTitlesMatchCatalog() throws {
        let container = try seededContainer()
        let catalog = try fetchCatalog(in: container)
        let index = ExerciseCatalogMatcher.buildAliasIndex(catalog: catalog)

        let sampleTitles = CatalogMatchReporter.geminiImportSampleTitles
        for title in sampleTitles {
            let matchTitle = ParsedWorkoutTitle.catalogMatchTitle(from: title)
            let result = ExerciseCatalogMatcher.match(
                importedTitle: matchTitle,
                catalog: catalog,
                aliasIndex: index
            )
            #expect(result.entry != nil, "Expected catalog entry for \(title)")
            #expect(result.flag != .unmatched, "Expected match or review for \(title)")
            #expect(result.confidence >= 0.7, "Expected confidence >= 0.7 for \(title)")
        }

        let lateral = ExerciseCatalogMatcher.match(
            importedTitle: "Dumbbell Lateral Raise",
            catalog: catalog,
            aliasIndex: index
        )
        #expect(lateral.entry?.canonicalName.lowercased().contains("lateral raise") == true)

        let chestPress = ExerciseCatalogMatcher.match(
            importedTitle: "Machine Chest Press",
            catalog: catalog,
            aliasIndex: index
        )
        #expect(chestPress.entry?.equipment == .machine)
        #expect(chestPress.entry?.primaryMuscles.contains(.chest) == true)

        let triceps = ExerciseCatalogMatcher.match(
            importedTitle: "Cable Triceps Extension",
            catalog: catalog,
            aliasIndex: index
        )
        #expect(triceps.entry?.equipment == .cable)
        #expect(triceps.entry?.primaryMuscles.contains(.triceps) == true)
    }

    @Test func hevyFixtureMatchReportCoversDistinctTitles() throws {
        let container = try seededContainer()
        let context = ModelContext(container)
        let csvURL = URL(fileURLWithPath: "/Users/cameronro/Development/Signal/fixtures/HevyExport.csv")
        let csvData = try Data(contentsOf: csvURL)
        let parsed = try HevyCSVParser.parse(data: csvData, calendar: Self.utcCalendar)
        _ = try WorkoutStore.upsert(
            parsedSessions: parsed.sessions,
            source: HevyCSVImporter.importSource,
            in: context
        )
        let report = try CatalogLinkService.linkAllWorkoutExercises(in: context)
        let distinct = Set(parsed.sessions.flatMap(\.exercises).map(\.exerciseTitle)).count
        #expect(report.matched.count + report.review.count == distinct)
        #expect(report.matchTableLines.count == report.matched.count)
    }

    private func seededContainer() throws -> ModelContainer {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        _ = try ExerciseCatalogSeeder.seedIfNeeded(in: context)
        return container
    }

    private func fetchCatalog(in container: ModelContainer) throws -> [ExerciseCatalog] {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<ExerciseCatalog>())
    }

    private static func utcDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        return utcCalendar.startOfDay(for: utcCalendar.date(from: components)!)
    }
}

private final class BundleToken {}
