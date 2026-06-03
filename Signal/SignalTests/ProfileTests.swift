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
