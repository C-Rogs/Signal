import SwiftData
import SwiftUI

struct WorkoutSwapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    currentExerciseCard

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What is unavailable?")
                            .font(.metadataCaption.weight(.semibold))
                            .foregroundStyle(Color("TextSecondary"))
                        TextField("Bench is occupied…", text: $constraintText, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(12)
                            .trainSurfaceCard(cornerRadius: 12)
                    }

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView("Finding a swap…")
                            Spacer()
                        }
                        .padding(.vertical, 16)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(Color("Warning"))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .trainSurfaceCard(cornerRadius: 12)
                    }

                    if let suggestion, let plan {
                        suggestionCard(suggestion: suggestion, plan: plan)
                    }

                    Button {
                        Task { await runSuggest() }
                    } label: {
                        Text(suggestion == nil ? "Suggest Swap" : "Suggest Again")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("Primary"))
                    .disabled(isLoading)
                }
                .padding(TrainChrome.horizontalPadding)
                .padding(.vertical, 8)
            }
            .background(screenBackground.ignoresSafeArea())
            .navigationTitle("Swap with Signal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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

    private var screenBackground: Color {
        TrainChrome.screenBackground(colorScheme: colorScheme)
    }

    private var currentExerciseCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current exercise")
                .font(.metadataCaption.weight(.semibold))
                .foregroundStyle(Color("TextSecondary"))
            Text(exercise.exerciseTitle)
                .font(.headline)
                .foregroundStyle(Color("TextPrimary"))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainSurfaceCard(cornerRadius: 12)
    }

    @ViewBuilder
    private func suggestionCard(suggestion: WorkoutSwapSuggestion, plan: SwapSetPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TrainSectionHeader(title: "Suggestion")

            Text(suggestion.substitute.canonicalName)
                .font(.headline)
                .foregroundStyle(Color("TextPrimary"))
            Text(suggestion.rationale)
                .font(.body)
                .foregroundStyle(Color("TextSecondary"))

            TrainStatusChip(title: plan.progressionIntent.chipLabel, style: .positive)

            if let note = plan.noHistoryNote {
                TrainStatusChip(title: note, style: .warning)
            }

            VStack(spacing: 6) {
                ForEach(Array(plan.sets.enumerated()), id: \.offset) { _, template in
                    setPreviewRow(template)
                }
            }

            Button {
                requestApply(catalog: suggestion.substitute, plan: plan)
            } label: {
                Text("Apply Swap")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("Primary"))
            .disabled(plan.sets.isEmpty)

            Button("Pick Manually") {
                showManualPicker = true
            }
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(14)
        .trainSurfaceCard(cornerRadius: 12)
    }

    private func setPreviewRow(_ template: SwapSetTemplate) -> some View {
        let typeLabel = WorkoutSetType(storageValue: template.setType) == .warmup ? "Warmup" : "Working"
        return HStack {
            Text(typeLabel)
                .font(.metadataCaption.weight(.semibold))
                .foregroundStyle(Color("TextSecondary"))
            Spacer()
            Text(setPreviewDetail(template))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color("TextPrimary"))
        }
        .padding(.vertical, 4)
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
