import Foundation
import SwiftData
import Testing
@testable import Signal

@MainActor
struct ProfileTests {
    @Test func bodyweightEntryIsAppendOnly() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)

        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = firstDate.addingTimeInterval(86_400)
        _ = try ProfileGoalRepository.appendBodyweight(kg: 80, date: firstDate, in: context)
        _ = try ProfileGoalRepository.appendBodyweight(kg: 81.5, date: secondDate, in: context)

        let entries = try ProfileGoalRepository.fetchBodyweightEntries(in: context)
        #expect(entries.count == 2)
        #expect(entries.contains { abs($0.kg - 80) < 0.001 })
        #expect(entries.contains { abs($0.kg - 81.5) < 0.001 })

        let profile = try ProfileGoalRepository.fetchOrCreateProfile(in: context)
        #expect(abs((profile.bodyweightKg ?? 0) - 81.5) < 0.001)
    }

    @Test func goalTypeDefaultRIRMatchesCanonicalValues() {
        #expect(GoalType.hypertrophy.defaultRIR == 2)
        #expect(GoalType.strength.defaultRIR == 1)
        #expect(GoalType.powerlifting.defaultRIR == 0)
        #expect(GoalType.generalFitness.defaultRIR == 2)
        for goal in GoalType.allCases {
            #expect((0 ... 5).contains(goal.defaultRIR))
        }
    }

    @Test func freshInstallLoadLeavesStoreEmptyUntilSave() async throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let viewModel = ProfileGoalsViewModel(
            modelContext: context,
            unitPreferences: UnitPreferences()
        )
        await viewModel.load()

        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<TrainingGoal>()) == 0)
        #expect(viewModel.heightCmText.isEmpty)
        #expect(viewModel.bodyweightDisplayText.isEmpty)
    }

    @Test func fetchOrCreateProfileIsIdempotent() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)

        let first = try ProfileGoalRepository.fetchOrCreateProfile(in: context)
        let second = try ProfileGoalRepository.fetchOrCreateProfile(in: context)

        #expect(first.persistentModelID == second.persistentModelID)
        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 1)
    }

    @Test func fetchOrCreateTrainingGoalIsIdempotent() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)

        let first = try ProfileGoalRepository.fetchOrCreateTrainingGoal(in: context)
        let second = try ProfileGoalRepository.fetchOrCreateTrainingGoal(in: context)

        #expect(first.persistentModelID == second.persistentModelID)
        #expect(try context.fetchCount(FetchDescriptor<TrainingGoal>()) == 1)
    }

    @Test func appendBodyweightCreatesProfileWhenMissing() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)

        #expect(try ProfileGoalRepository.fetchProfile(in: context) == nil)
        _ = try ProfileGoalRepository.appendBodyweight(kg: 75, in: context)
        let profile = try ProfileGoalRepository.fetchProfile(in: context)
        #expect(profile != nil)
        #expect(abs((profile?.bodyweightKg ?? 0) - 75) < 0.001)
    }

    @Test func primaryGoalFallsBackToHypertrophyWhenNoGoalSaved() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        #expect(ProfileGoalRepository.primaryGoal(in: context) == .hypertrophy)
    }

    @Test func primaryGoalReadsSavedGoal() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let goal = try ProfileGoalRepository.fetchOrCreateTrainingGoal(in: context)
        goal.primaryGoal = .strength
        try context.save()
        #expect(ProfileGoalRepository.primaryGoal(in: context) == .strength)
    }

    @Test func targetRIRFallsBackWhenNoGoalSaved() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        #expect(ProfileGoalRepository.targetRIR(in: context) == ProfileGoalRepository.fallbackTargetRIR)
    }

    @Test func targetRIRReadsSavedGoal() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let goal = try ProfileGoalRepository.fetchOrCreateTrainingGoal(in: context)
        goal.primaryGoal = .powerlifting
        goal.targetRIR = 0
        try context.save()
        #expect(ProfileGoalRepository.targetRIR(in: context) == 0)
    }

    @Test func applyHealthSnapshotUpdatesRecentBodyMass() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let profile = try ProfileGoalRepository.fetchOrCreateProfile(in: context)
        let measuredAt = Date(timeIntervalSince1970: 1_750_000_000)
        var snapshot = ProfileHealthSnapshot()
        snapshot.bodyMassKg = 82.3
        snapshot.bodyMassMeasuredAt = measuredAt
        snapshot.sources = [.healthKitLive]

        let result = try ProfileGoalRepository.applyHealthSnapshot(
            snapshot,
            to: profile,
            in: context,
            now: measuredAt.addingTimeInterval(3600)
        )
        #expect(result.updatedBodyweight)
        #expect(abs((profile.bodyweightKg ?? 0) - 82.3) < 0.001)
        let entries = try ProfileGoalRepository.fetchBodyweightEntries(in: context)
        #expect(entries.count == 1)
    }

    @Test func applyHealthSnapshotFillsDateOfBirthWhenEmpty() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let profile = try ProfileGoalRepository.fetchOrCreateProfile(in: context)
        let dob = Date(timeIntervalSince1970: 500_000_000)
        var snapshot = ProfileHealthSnapshot()
        snapshot.dateOfBirth = dob
        snapshot.sources = [.healthKitLive]

        let result = try ProfileGoalRepository.applyHealthSnapshot(snapshot, to: profile, in: context)
        #expect(result.filledDateOfBirth)
        #expect(profile.dateOfBirth == dob)
    }

    @Test func applyHealthSnapshotDoesNotOverwriteExistingDateOfBirth() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let profile = try ProfileGoalRepository.fetchOrCreateProfile(in: context)
        let existing = Date(timeIntervalSince1970: 400_000_000)
        profile.dateOfBirth = existing
        try context.save()

        var snapshot = ProfileHealthSnapshot()
        snapshot.dateOfBirth = Date(timeIntervalSince1970: 500_000_000)

        let result = try ProfileGoalRepository.applyHealthSnapshot(snapshot, to: profile, in: context)
        #expect(!result.filledDateOfBirth)
        #expect(profile.dateOfBirth == existing)
    }

    @Test func applyHealthSnapshotSkipsStaleBodyMass() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let profile = try ProfileGoalRepository.fetchOrCreateProfile(in: context)
        let staleDate = Date(timeIntervalSince1970: 1_000_000_000)
        var snapshot = ProfileHealthSnapshot()
        snapshot.bodyMassKg = 90
        snapshot.bodyMassMeasuredAt = staleDate

        let result = try ProfileGoalRepository.applyHealthSnapshot(
            snapshot,
            to: profile,
            in: context,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(!result.updatedBodyweight)
    }

    @Test func strengthGoalPresetsTargetRIRSlider() {
        let container = try! SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let viewModel = ProfileGoalsViewModel(
            modelContext: context,
            unitPreferences: UnitPreferences()
        )
        viewModel.primaryGoal = .strength
        viewModel.targetRIRManuallyAdjusted = false
        viewModel.primaryGoalDidChange()
        #expect(viewModel.targetRIR == GoalType.strength.defaultRIR)
        #expect(viewModel.targetRIR == 1)
    }
}
