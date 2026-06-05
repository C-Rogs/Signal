import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ExerciseDetailViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case history = "History"
        case progress = "Progress"
        case howTo = "How-to"

        var id: String { rawValue }
    }

    let route: ExerciseDetailRoute

    var selectedTab: Tab = .history
    var catalogEntry: ExerciseCatalog?
    var displayTitle: String = ""
    var historySessions: [ExerciseHistorySession] = []
    var e1rmChartPoints: [DashboardChartPoint] = []
    var prE1RMKg: Double?
    var prLoad: ExerciseLoadPR?
    var averageWorkingSetVolumeKg: Double?
    var instructions: [String]?

    init(route: ExerciseDetailRoute) {
        self.route = route
        displayTitle = route.exerciseTitle
    }

    func load(modelContext: ModelContext, unitPreferences: UnitPreferences) {
        let formatter = DisplayUnitFormatter(preferences: unitPreferences)
        catalogEntry = resolveCatalog(in: modelContext)
        displayTitle = catalogEntry?.canonicalName ?? route.exerciseTitle

        historySessions = (try? ExerciseDetailHistoryLoader.loadRecentSessions(
            catalogEntry: catalogEntry,
            exerciseTitle: route.exerciseTitle,
            limit: 10,
            formatter: formatter,
            in: modelContext
        )) ?? []

        let exerciseID = exerciseProgressID()
        if let rows = try? ExerciseProgressStore.fetchHistory(exerciseID: exerciseID, in: modelContext) {
            e1rmChartPoints = rows.map {
                DashboardChartPoint(date: $0.sessionDate, value: $0.e1RM_kg)
            }
            prE1RMKg = rows.map(\.e1RM_kg).max()
        }

        prLoad = try? ExerciseVolumeCalculator.bestLoadPR(
            catalogEntry: catalogEntry,
            exerciseTitle: route.exerciseTitle,
            in: modelContext
        )
        averageWorkingSetVolumeKg = try? ExerciseVolumeCalculator.averageWorkingSetVolume(
            catalogEntry: catalogEntry,
            exerciseTitle: route.exerciseTitle,
            sessionLimit: 8,
            in: modelContext
        )

        instructions = ExerciseGuideLoader.guide(for: catalogEntry)
            ?? ExerciseGuideLoader.guide(for: route.exerciseTitle)
    }

    private func resolveCatalog(in context: ModelContext) -> ExerciseCatalog? {
        if let catalogID = route.catalogID,
           let entry = context.model(for: catalogID) as? ExerciseCatalog {
            return entry
        }
        let catalog = (try? context.fetch(FetchDescriptor<ExerciseCatalog>())) ?? []
        let match = ExerciseCatalogMatcher.match(importedTitle: route.exerciseTitle, catalog: catalog)
        return match.entry
    }

    private func exerciseProgressID() -> String {
        if let name = catalogEntry?.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return route.exerciseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
