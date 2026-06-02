import Foundation
import SwiftData

@Model
final class WellnessEntry {
    var capturedAt: Date
    var energy: Int
    var mood: Int
    var stress: Int
    var sorenessByMuscleRaw: [String: Int]
    var notes: String?

    var session: WorkoutSession?

    init(
        capturedAt: Date = .now,
        energy: Int,
        mood: Int,
        stress: Int,
        sorenessByMuscleRaw: [String: Int] = [:],
        notes: String? = nil,
        session: WorkoutSession? = nil
    ) {
        self.capturedAt = capturedAt
        self.energy = energy
        self.mood = mood
        self.stress = stress
        self.sorenessByMuscleRaw = sorenessByMuscleRaw
        self.notes = notes
        self.session = session
    }
}
