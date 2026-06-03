import Foundation
import SwiftData

@Model
final class UserProfile {
    var profileKey: String
    var heightCm: Double?
    var bodyweightKg: Double?
    var dateOfBirth: Date?
    var biologicalSex: String?

    init(
        profileKey: String = ProfileGoalRepository.profileKey,
        heightCm: Double? = nil,
        bodyweightKg: Double? = nil,
        dateOfBirth: Date? = nil,
        biologicalSex: String? = nil
    ) {
        self.profileKey = profileKey
        self.heightCm = heightCm
        self.bodyweightKg = bodyweightKg
        self.dateOfBirth = dateOfBirth
        self.biologicalSex = biologicalSex
    }
}
