import Foundation
import SwiftData

@Model
final class WorkoutExercise {
    var exerciseTitle: String
    var notes: String?
    var supersetId: String?
    var order: Int
    var catalogMatchFlag: String?

    var session: WorkoutSession?
    var catalogEntry: ExerciseCatalog?

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.exercise)
    var sets: [SetEntry] = []

    init(
        exerciseTitle: String,
        notes: String? = nil,
        supersetId: String? = nil,
        order: Int,
        catalogEntry: ExerciseCatalog? = nil,
        catalogMatchFlag: String? = nil
    ) {
        self.exerciseTitle = exerciseTitle
        self.notes = notes
        self.supersetId = supersetId
        self.order = order
        self.catalogEntry = catalogEntry
        self.catalogMatchFlag = catalogMatchFlag
    }

    var catalogMatch: CatalogMatchFlag? {
        guard let catalogMatchFlag else { return nil }
        return CatalogMatchFlag(rawValue: catalogMatchFlag)
    }
}
