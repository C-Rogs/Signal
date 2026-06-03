import Foundation
import FoundationModels
import SwiftData

struct MuscleVolumeTool: Tool {
    let modelContainer: ModelContainer

    let name = "muscleVolume"
    let description = "Current week set volume and MEV/MAV/MRV status for a muscle group."

    @Generable
    struct Arguments {
        @Guide(description: "Muscle group name, e.g. chest or quads")
        var muscleName: String
    }

    func call(arguments: Arguments) async throws -> String {
        let trimmed = arguments.muscleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let group = Self.matchMuscleGroup(trimmed) else {
            return "Unknown muscle: \(arguments.muscleName)."
        }

        let snapshot = await DerivedMetricsService.shared.snapshot(modelContainer: modelContainer)
        return await MainActor.run {
            Self.formatVolume(group: group, snapshot: snapshot)
        }
    }

    @MainActor
    private static func formatVolume(group: MuscleGroup, snapshot: DerivedMetricsSnapshot) -> String {
        let row = snapshot.weeklyVolume.first { $0.muscleGroup == group }
        let landmarks = group.landmarks
        let setsText = row.map { VolumeCalculator.integerSetCount(from: $0.fractionalSets) } ?? "0"
        let status = row?.status.badgeLabel ?? VolumeStatus.belowMEV.badgeLabel
        return "Current week: \(setsText) sets. Status: \(status). MEV \(landmarks.mev) / MAV \(landmarks.mav) / MRV \(landmarks.mrv)."
    }

    private static func matchMuscleGroup(_ name: String) -> MuscleGroup? {
        let needle = name.lowercased()
        if let exact = MuscleGroup(rawValue: needle) {
            return exact
        }
        return MuscleGroup.allCases.first { group in
            group.rawValue.lowercased().contains(needle) || needle.contains(group.rawValue.lowercased())
        }
    }
}
