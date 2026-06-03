import Foundation
import os
import SwiftData

enum ProfileGoalRepository {
    static let profileKey = "me"
    static let primaryGoalKey = "primary"

    static let fallbackTargetRIR = 2

    static func fetchOrCreateProfile(in context: ModelContext) throws -> UserProfile {
        try resolveSingleton(
            matches: fetchAllProfiles(in: context),
            make: { UserProfile(profileKey: profileKey) },
            insert: { context.insert($0) },
            logCreated: "created default user profile",
            in: context
        )
    }

    static func fetchProfile(in context: ModelContext) throws -> UserProfile? {
        try fetchAllProfiles(in: context).first
    }

    static func fetchOrCreateTrainingGoal(in context: ModelContext) throws -> TrainingGoal {
        try resolveSingleton(
            matches: fetchAllTrainingGoals(in: context),
            make: { TrainingGoal(goalKey: primaryGoalKey) },
            insert: { context.insert($0) },
            logCreated: "created default training goal",
            in: context
        )
    }

    static func fetchTrainingGoal(in context: ModelContext) throws -> TrainingGoal? {
        try fetchAllTrainingGoals(in: context).first
    }

    private static func fetchAllProfiles(in context: ModelContext) throws -> [UserProfile] {
        let key = profileKey
        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.profileKey == key }
        )
        return try context.fetch(descriptor)
    }

    private static func fetchAllTrainingGoals(in context: ModelContext) throws -> [TrainingGoal] {
        let key = primaryGoalKey
        let descriptor = FetchDescriptor<TrainingGoal>(
            predicate: #Predicate { $0.goalKey == key }
        )
        return try context.fetch(descriptor)
    }

    private static func resolveSingleton<Model: PersistentModel>(
        matches: [Model],
        make: () -> Model,
        insert: (Model) -> Void,
        logCreated: String,
        in context: ModelContext
    ) throws -> Model {
        if let first = matches.first {
            if matches.count > 1 {
                for duplicate in matches.dropFirst() {
                    context.delete(duplicate)
                }
                try context.save()
                Log.ui.error("removed duplicate singleton rows count=\(matches.count, privacy: .public)")
            }
            return first
        }
        let created = make()
        insert(created)
        try context.save()
        Log.ui.info("\(logCreated, privacy: .public)")
        return created
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

    static func applyHealthSnapshot(
        _ snapshot: ProfileHealthSnapshot,
        in context: ModelContext,
        now: Date = .now
    ) throws -> ProfileHealthApplyResult {
        guard snapshot.hasAnyData else {
            return ProfileHealthApplyResult()
        }
        let profile = try fetchOrCreateProfile(in: context)
        return try applyHealthSnapshot(snapshot, to: profile, in: context, now: now)
    }

    static func applyHealthSnapshot(
        _ snapshot: ProfileHealthSnapshot,
        to profile: UserProfile,
        in context: ModelContext,
        now: Date = .now
    ) throws -> ProfileHealthApplyResult {
        var result = ProfileHealthApplyResult()

        if let kg = snapshot.bodyMassKg,
           let measuredAt = snapshot.bodyMassMeasuredAt,
           ProfileHealthKitReader.isRecentBodyMass(measuredAt: measuredAt, now: now)
        {
            let entries = try fetchBodyweightEntries(in: context)
            let latestEntryDate = entries.first?.date
            let healthIsNewer = latestEntryDate.map { measuredAt > $0 } ?? true
            if healthIsNewer || profile.bodyweightKg == nil {
                _ = try appendBodyweight(kg: kg, date: measuredAt, in: context, save: false)
                result.updatedBodyweight = true
            }
        }

        if profile.dateOfBirth == nil, let dateOfBirth = snapshot.dateOfBirth {
            profile.dateOfBirth = dateOfBirth
            result.filledDateOfBirth = true
        }

        if profile.biologicalSex == nil, let sex = snapshot.biologicalSexStorage {
            profile.biologicalSex = sex
            result.filledBiologicalSex = true
        }

        if result.didChangeProfile {
            try context.save()
            result.summaryMessage = result.buildSummary(snapshot: snapshot)
            Log.ui.info("applied health snapshot to profile")
        }

        return result
    }
}

struct ProfileHealthApplyResult: Equatable, Sendable {
    var updatedBodyweight = false
    var filledDateOfBirth = false
    var filledBiologicalSex = false
    var summaryMessage: String?

    var didChangeProfile: Bool {
        updatedBodyweight || filledDateOfBirth || filledBiologicalSex
    }

    func buildSummary(snapshot: ProfileHealthSnapshot) -> String {
        var parts: [String] = []
        if updatedBodyweight {
            let source = snapshot.sources.contains(.healthKitLive) ? "Apple Health" : "your health sync"
            parts.append("body weight from \(source)")
        }
        if filledDateOfBirth {
            parts.append("date of birth from Apple Health")
        }
        if filledBiologicalSex {
            parts.append("sex from Apple Health")
        }
        return "Updated " + parts.joined(separator: ", ") + "."
    }
}
