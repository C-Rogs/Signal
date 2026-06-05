import SwiftData
import SwiftUI

struct WorkoutSwapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LiveWorkoutCoordinator.self) private var coordinator
    @Environment(UnitPreferences.self) private var unitPreferences

    let exercise: WorkoutExercise
    let store: LiveWorkoutStore
    let recoveryScore: RecoveryScore
    let personalReadiness: PersonalReadinessProfile?

    let onApplied: () -> Void

    @State private var constraintText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var suggestion: WorkoutSwapSuggestion?
    @State private var plan: SwapSetPlan?
    @State private var showManualPicker = false
    @State private var showCompletedSetsConfirm = false
    @State private var pendingApply: (ExerciseCatalog, SwapSetPlan)?

    private var formatter: DisplayUnitFormatter {
        DisplayUnitFormatter(preferences: unitPreferences)
    }

    private var deloadActive: Bool {
        DeloadSuggestionReader.isDeloadActive(in: modelContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(exercise.exerciseTitle)
                        .font(.headline)
                } header: {
                    Text("Current exercise")
                }

                Section {
                    TextField("Bench is occupied…", text: $constraintText, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("What is unavailable?")
                }

                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Finding a swap…")
                            Spacer()
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Color("Warning"))
                            .font(.subheadline)
                    }
                }

                if let suggestion, let plan {
                    suggestionSection(suggestion: suggestion, plan: plan)
                }
            }
            .navigationTitle("Swap with Signal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Suggest") {
                        Task { await runSuggest() }
                    }
                    .disabled(isLoading)
                }
            }
            .sheet(isPresented: $showManualPicker) {
                ExercisePickerView { catalog in
                    applyManualPick(catalog)
                }
            }
            .confirmationDialog(
                "Replace remaining sets?",
                isPresented: $showCompletedSetsConfirm,
                titleVisibility: .visible
            ) {
                Button("Apply swap") {
                    if let pendingApply {
                        performSwap(catalog: pendingApply.0, plan: pendingApply.1)
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingApply = nil
                }
            } message: {
                let count = WorkoutSwapOrchestrator.completedWorkingSetCount(for: exercise)
                Text("You logged \(count) working set\(count == 1 ? "" : "s") on \(exercise.exerciseTitle). Swap will replace remaining sets.")
            }
        }
    }

    @ViewBuilder
    private func suggestionSection(suggestion: WorkoutSwapSuggestion, plan: SwapSetPlan) -> some View {
        Section {
            Text(suggestion.substitute.canonicalName)
                .font(.headline)
            Text(suggestion.rationale)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(plan.progressionIntent.chipLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color("Primary"))

            if let note = plan.noHistoryNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Color("Warning"))
            }

            ForEach(Array(plan.sets.enumerated()), id: \.offset) { _, template in
                setPreviewRow(template)
            }
        } header: {
            Text("Suggestion")
        }

        Section {
            Button("Apply swap") {
                requestApply(catalog: suggestion.substitute, plan: plan)
            }
            .disabled(plan.sets.isEmpty)

            Button("Pick manually") {
                showManualPicker = true
            }
        }
    }

    private func setPreviewRow(_ template: SwapSetTemplate) -> some View {
        let typeLabel = WorkoutSetType(storageValue: template.setType) == .warmup ? "Warmup" : "Working"
        return HStack {
            Text(typeLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(setPreviewDetail(template))
                .font(.subheadline.monospacedDigit())
        }
    }

    private func setPreviewDetail(_ template: SwapSetTemplate) -> String {
        if let weight = template.weightKg, let reps = template.reps {
            return "\(formatter.formatMassKg(weight)) × \(reps)"
        }
        if let reps = template.reps {
            return "× \(reps)"
        }
        return "Enter load"
    }

    private func runSuggest() async {
        isLoading = true
        errorMessage = nil
        suggestion = nil
        plan = nil
        defer { isLoading = false }

        do {
            let result = try await WorkoutSwapOrchestrator.buildSuggestion(
                exercise: exercise,
                constraint: constraintText,
                recoveryScore: recoveryScore,
                personalReadiness: personalReadiness,
                deloadActive: deloadActive,
                in: modelContext
            )
            suggestion = result.0
            plan = result.1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyManualPick(_ catalog: ExerciseCatalog) {
        do {
            let manualPlan = try WorkoutSwapOrchestrator.buildPlan(
                exercise: exercise,
                substitute: catalog,
                recoveryScore: recoveryScore,
                personalReadiness: personalReadiness,
                deloadActive: deloadActive,
                in: modelContext
            )
            suggestion = WorkoutSwapSuggestion(
                substitute: catalog,
                rationale: "Manual pick.",
                usedFoundationModel: false
            )
            plan = manualPlan
            showManualPicker = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestApply(catalog: ExerciseCatalog, plan: SwapSetPlan) {
        if WorkoutSwapOrchestrator.completedWorkingSetCount(for: exercise) > 0 {
            pendingApply = (catalog, plan)
            showCompletedSetsConfirm = true
        } else {
            performSwap(catalog: catalog, plan: plan)
        }
    }

    private func performSwap(catalog: ExerciseCatalog, plan: SwapSetPlan) {
        do {
            let exerciseID = exercise.persistentModelID
            try store.swapExercise(
                exercise,
                catalogEntry: catalog,
                exerciseTitle: catalog.canonicalName,
                plan: plan
            )
            coordinator.requestScroll(to: exerciseID)
            onApplied()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingApply = nil
    }
}
