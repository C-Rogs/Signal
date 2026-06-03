import Foundation
import Observation
import os
import SwiftData

enum ProfileGoalsSaveState: Equatable {
    case idle
    case saving
    case saved(message: String)
    case failed(message: String)
}

@MainActor
@Observable
final class ProfileGoalsViewModel {
    var heightCmText = ""
    var bodyweightDisplayText = ""
    var dateOfBirth = Date()
    var includesDateOfBirth = false
    var biologicalSex: BiologicalSexOption = .unspecified

    var primaryGoal: GoalType = .generalFitness
    var weeklyTrainingDays = 4
    var targetRIR = GoalType.generalFitness.defaultRIR
    var goalNotes = ""
    var targetRIRManuallyAdjusted = false

    var isLoading = false
    var saveState: ProfileGoalsSaveState = .idle
    var healthBannerMessage: String?
    var healthAccessHint: String?

    private let modelContext: ModelContext
    private let unitPreferences: UnitPreferences
    private let healthKitManager: HealthKitManager?
    private var formatter: DisplayUnitFormatter {
        DisplayUnitFormatter(preferences: unitPreferences)
    }

    init(
        modelContext: ModelContext,
        unitPreferences: UnitPreferences,
        healthKitManager: HealthKitManager? = nil
    ) {
        self.modelContext = modelContext
        self.unitPreferences = unitPreferences
        self.healthKitManager = healthKitManager
    }

    var canSave: Bool {
        if case .saving = saveState { return false }
        return true
    }

    var saveButtonTitle: String {
        switch saveState {
        case .saving:
            return "Saving…"
        case .saved:
            return "Saved"
        default:
            return "Save profile and goal"
        }
    }

    func load() async {
        isLoading = true
        saveState = .idle
        healthBannerMessage = nil
        healthAccessHint = nil
        defer { isLoading = false }

        do {
            await syncFromHealth()
            if let profile = try ProfileGoalRepository.fetchProfile(in: modelContext) {
                populateFields(from: profile)
            } else {
                resetProfileFieldsToDefaults()
            }
            populateGoalFields()
        } catch {
            saveState = .failed(message: error.localizedDescription)
            Log.ui.error("profile goals load failed: \(String(describing: error), privacy: .public)")
        }
    }

    func primaryGoalDidChange() {
        if !targetRIRManuallyAdjusted {
            targetRIR = primaryGoal.defaultRIR
        }
    }

    func targetRIRDidChange() {
        targetRIRManuallyAdjusted = targetRIR != primaryGoal.defaultRIR
    }

    func save() async {
        guard canSave else { return }
        saveState = .saving
        healthBannerMessage = nil

        do {
            let profile = try ProfileGoalRepository.fetchOrCreateProfile(in: modelContext)
            profile.heightCm = Self.parsePositiveDouble(heightCmText)
            profile.dateOfBirth = includesDateOfBirth ? dateOfBirth : nil
            profile.biologicalSex = biologicalSex.storageValue
            if let kg = formatter.parseMassInputToKg(from: bodyweightDisplayText) {
                _ = try ProfileGoalRepository.appendBodyweight(kg: kg, in: modelContext, save: false)
            }

            let goal = try ProfileGoalRepository.fetchOrCreateTrainingGoal(in: modelContext)
            goal.primaryGoal = primaryGoal
            goal.weeklyTrainingDays = min(7, max(1, weeklyTrainingDays))
            goal.targetRIR = min(5, max(0, targetRIR))
            goal.updatedAt = .now
            let trimmedNotes = goalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            goal.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

            try modelContext.save()
            Log.ui.info(
                "saved profile and goal days=\(goal.weeklyTrainingDays, privacy: .public) rir=\(goal.targetRIR, privacy: .public)"
            )
            NotificationCenter.default.post(name: .goalDidChange, object: nil)
            saveState = .saved(
                message: "Profile and training goal saved. Warmup and cue targets update on your next set."
            )
        } catch {
            saveState = .failed(message: error.localizedDescription)
            Log.ui.error("profile goals save failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func syncFromHealth() async {
        guard let healthKitManager else {
            healthAccessHint = "Connect Apple Health under Profile → Import to auto-fill recent weight and birthday."
            await syncFromDailyMetricsOnly()
            return
        }

        switch healthKitManager.accessState {
        case .ready:
            let snapshot = await healthKitManager.fetchProfileHealthSnapshot(modelContext: modelContext)
            applySnapshot(snapshot)
        case .notDetermined, .denied:
            healthAccessHint =
                "Allow Health access in Profile → Import to pull recent body weight and birthday from Apple Health."
            await syncFromDailyMetricsOnly()
        case .unavailable:
            healthAccessHint = "Apple Health is not available on this device."
            await syncFromDailyMetricsOnly()
        }
    }

    private func syncFromDailyMetricsOnly() async {
        guard let cached = ProfileHealthKitReader.latestBodyMassFromDailyMetrics(in: modelContext) else {
            return
        }
        var snapshot = ProfileHealthSnapshot()
        snapshot.bodyMassKg = cached.kg
        snapshot.bodyMassMeasuredAt = cached.measuredAt
        snapshot.sources = [.dailyMetricCache]
        applySnapshot(snapshot)
    }

    private func applySnapshot(_ snapshot: ProfileHealthSnapshot) {
        guard snapshot.hasAnyData else { return }
        do {
            let result = try ProfileGoalRepository.applyHealthSnapshot(snapshot, in: modelContext)
            if let message = result.summaryMessage {
                healthBannerMessage = message
            }
        } catch {
            Log.ui.error(
                "apply health snapshot failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func resetProfileFieldsToDefaults() {
        heightCmText = ""
        bodyweightDisplayText = ""
        includesDateOfBirth = false
        biologicalSex = .unspecified
    }

    private func populateFields(from profile: UserProfile) {
        if let heightCm = profile.heightCm {
            heightCmText = Self.formatDecimal(heightCm)
        } else {
            heightCmText = ""
        }
        bodyweightDisplayText = formatter.displayMassInputKg(profile.bodyweightKg)
        if let dob = profile.dateOfBirth {
            dateOfBirth = dob
            includesDateOfBirth = true
        } else {
            includesDateOfBirth = false
        }
        biologicalSex = BiologicalSexOption.from(storage: profile.biologicalSex)
    }

    private func populateGoalFields() {
        do {
            if let goal = try ProfileGoalRepository.fetchTrainingGoal(in: modelContext) {
                primaryGoal = goal.primaryGoal
                weeklyTrainingDays = goal.weeklyTrainingDays
                targetRIR = goal.targetRIR
                goalNotes = goal.notes ?? ""
                targetRIRManuallyAdjusted = goal.targetRIR != goal.primaryGoal.defaultRIR
            } else {
                applyDefaultRIRForSelectedGoal()
            }
        } catch {
            saveState = .failed(message: error.localizedDescription)
        }
    }

    private func applyDefaultRIRForSelectedGoal() {
        targetRIR = primaryGoal.defaultRIR
        targetRIRManuallyAdjusted = false
    }

    private static func parsePositiveDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private static func formatDecimal(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

enum BiologicalSexOption: String, CaseIterable, Identifiable {
    case unspecified
    case male
    case female
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unspecified: "Not specified"
        case .male: "Male"
        case .female: "Female"
        case .other: "Other"
        }
    }

    var storageValue: String? {
        switch self {
        case .unspecified: nil
        case .male: "male"
        case .female: "female"
        case .other: "other"
        }
    }

    static func from(storage: String?) -> BiologicalSexOption {
        guard let storage else { return .unspecified }
        return BiologicalSexOption(rawValue: storage) ?? .unspecified
    }
}
