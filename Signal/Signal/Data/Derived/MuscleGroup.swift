import Foundation

enum MuscleGroup: String, CaseIterable, Codable, Sendable, Hashable {
    case chest
    case back
    case quads
    case hamstrings
    case glutes
    case shoulders
    case biceps
    case triceps
    case calves
    case abs

    var landmarks: (mev: Int, mav: Int, mrv: Int) {
        VolumeLandmarks.forMuscleGroup(self)
    }

    static func groups(for muscle: Muscle) -> [MuscleGroup] {
        switch muscle {
        case .chest:
            return [.chest]
        case .lats, .upperBack, .traps, .lowerBack:
            return [.back]
        case .quads:
            return [.quads]
        case .hamstrings:
            return [.hamstrings]
        case .glutes:
            return [.glutes]
        case .frontDelts, .sideDelts, .rearDelts:
            return [.shoulders]
        case .biceps, .forearms:
            return [.biceps]
        case .triceps:
            return [.triceps]
        case .calves:
            return [.calves]
        case .abs, .obliques:
            return [.abs]
        case .fullBody:
            return []
        }
    }
}

enum VolumeLandmarks {
    static func forMuscleGroup(_ group: MuscleGroup) -> (mev: Int, mav: Int, mrv: Int) {
        switch group {
        case .chest:
            return (8, 14, 22)
        case .back:
            return (10, 16, 24)
        case .quads:
            return (8, 16, 24)
        case .hamstrings:
            return (6, 12, 20)
        case .glutes:
            return (4, 12, 20)
        case .shoulders:
            return (8, 14, 20)
        case .biceps:
            return (6, 14, 20)
        case .triceps:
            return (6, 14, 18)
        case .calves:
            return (6, 12, 16)
        case .abs:
            return (0, 16, 24)
        }
    }
}

enum VolumeStatus: String, Sendable, Hashable {
    case belowMEV
    case mevToMAV
    case mavToMRV
    case aboveMRV

    static func status(fractionalSets: Double, landmarks: (mev: Int, mav: Int, mrv: Int)) -> VolumeStatus {
        let mev = Double(landmarks.mev)
        let mav = Double(landmarks.mav)
        let mrv = Double(landmarks.mrv)
        if fractionalSets < mev {
            return .belowMEV
        }
        if fractionalSets <= mav {
            return .mevToMAV
        }
        if fractionalSets <= mrv {
            return .mavToMRV
        }
        return .aboveMRV
    }

    var badgeLabel: String {
        switch self {
        case .belowMEV:
            return "Below MEV"
        case .mevToMAV:
            return "MEV to MAV"
        case .mavToMRV:
            return "MAV to MRV"
        case .aboveMRV:
            return "Above MRV"
        }
    }
}
