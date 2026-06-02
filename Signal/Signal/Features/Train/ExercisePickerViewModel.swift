import Foundation
import Observation
import SwiftData

struct ExercisePickerRow: Identifiable, Hashable, Sendable {
    let id: PersistentIdentifier
    let name: String
    let equipment: ExerciseEquipment
    let primaryMuscles: [Muscle]
    let isPickerDefault: Bool
}

@MainActor
@Observable
final class ExercisePickerViewModel {
    private(set) var rows: [ExercisePickerRow] = []
    private(set) var isLoading = true

    var searchText = ""
    var browseAllExercises = false
    var muscleFilter: Muscle?
    var equipmentFilter: ExerciseEquipment?

    private var recentIDs: [PersistentIdentifier] = []
    private var catalogByID: [PersistentIdentifier: ExerciseCatalog] = [:]

    func load(context: ModelContext) {
        isLoading = true
        recentIDs = ExerciseRecencyService.recentCatalogIDs(in: context)
        let catalog = (try? context.fetch(FetchDescriptor<ExerciseCatalog>())) ?? []
        catalogByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.persistentModelID, $0) })
        rows = catalog.map { entry in
            ExercisePickerRow(
                id: entry.persistentModelID,
                name: entry.canonicalName,
                equipment: entry.equipment,
                primaryMuscles: entry.primaryMuscles,
                isPickerDefault: entry.isPickerDefault
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        isLoading = false
    }

    func catalogEntry(for id: PersistentIdentifier) -> ExerciseCatalog? {
        catalogByID[id]
    }

    var recentRows: [ExercisePickerRow] {
        recentIDs.compactMap { id in rows.first { $0.id == id } }
    }

    var showSearchAllSection: Bool {
        browseAllExercises || !trimmedSearch.isEmpty
    }

    var commonRows: [ExercisePickerRow] {
        guard trimmedSearch.isEmpty else { return [] }
        return filtered(rows.filter(\.isPickerDefault))
    }

    var searchAllRows: [ExercisePickerRow] {
        guard showSearchAllSection else { return [] }
        let base = trimmedSearch.isEmpty ? rows : matchingSearch(in: rows)
        return filtered(base)
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchingSearch(in source: [ExercisePickerRow]) -> [ExercisePickerRow] {
        let query = trimmedSearch.lowercased()
        guard !query.isEmpty else { return source }
        return source.filter { $0.name.lowercased().contains(query) }
    }

    private func filtered(_ source: [ExercisePickerRow]) -> [ExercisePickerRow] {
        source.filter { row in
            if let muscleFilter, !row.primaryMuscles.contains(muscleFilter) {
                return false
            }
            if let equipmentFilter, row.equipment != equipmentFilter {
                return false
            }
            return true
        }
    }
}
