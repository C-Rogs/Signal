import Foundation
import os
import SwiftData

enum ProfileGoalRepository {
    static let profileKey = "me"
    static let primaryGoalKey = "primary"

    static let fallbackTargetRIR = 2

    static func fetchOrCreateProfile(in context: ModelContext) throws -> UserProfile {
        if let existing = try fetchProfile(in: context) {
            return existing
        }
        let profile = UserProfile(profileKey: profileKey)
        context.insert(profile)
        try context.save()
        Log.ui.info("created default user profile")
        return profile
    }

    static func fetchProfile(in context: ModelContext) throws -> UserProfile? {
        let key = profileKey
        var descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.profileKey == key }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func fetchOrCreateTrainingGoal(in context: ModelContext) throws -> TrainingGoal {
        if let existing = try fetchTrainingGoal(in: context) {
            return existing
        }
        let goal = TrainingGoal(goalKey: primaryGoalKey)
        context.insert(goal)
        try context.save()
        Log.ui.info("created default training goal")
        return goal
    }

    static func fetchTrainingGoal(in context: ModelContext) throws -> TrainingGoal? {
        let key = primaryGoalKey
        var descriptor = FetchDescriptor<TrainingGoal>(
            predicate: #Predicate { $0.goalKey == key }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func primaryGoal(in context: ModelContext) -> GoalType {
        do {
            return try fetchTrainingGoal(in: context)?.primaryGoal ?? .hypertrophy
        } catch {
            Log.ui.error("primaryGoal fetch failed: \(String(describing: error), privacy: .public)")
            return .hypertrophy
        }
    }

    static func targetRIR(in context: ModelContext) -> Int {
        do {
            guard let goal = try fetchTrainingGoal(in: context) else {
                return fallbackTargetRIR
            }
            return goal.targetRIR
        } catch {
            Log.ui.error("targetRIR fetch failed: \(String(describing: error), privacy: .public)")
            return fallbackTargetRIR
        }
    }

    @discardableResult
    static func appendBodyweight(
        kg: Double,
        date: Date = .now,
        in context: ModelContext,
        save: Bool = true
    ) throws -> BodyweightEntry {
        let entry = BodyweightEntry(date: date, kg: kg)
        context.insert(entry)
        let profile = try fetchOrCreateProfile(in: context)
        profile.bodyweightKg = kg
        if save {
            try context.save()
        }
        Log.ui.info("appended bodyweight entry kg=\(kg, privacy: .public)")
        return entry
    }

    static func fetchBodyweightEntries(in context: ModelContext) throws -> [BodyweightEntry] {
        let descriptor = FetchDescriptor<BodyweightEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }
}
