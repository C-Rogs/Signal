import Foundation
import SwiftData

@Model
final class WorkoutExercise {
    var exerciseTitle: String
    var notes: String?
    var supersetId: String?
    var order: Int

    var session: WorkoutSession?

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.exercise)
    var sets: [SetEntry] = []

    init(
        exerciseTitle: String,
        notes: String? = nil,
        supersetId: String? = nil,
        order: Int
    ) {
        self.exerciseTitle = exerciseTitle
        self.notes = notes
        self.supersetId = supersetId
        self.order = order
    }
}
