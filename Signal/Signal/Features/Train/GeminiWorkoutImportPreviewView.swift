import SwiftData
import SwiftUI

struct GeminiWorkoutImportPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LiveWorkoutCoordinator.self) private var coordinator
    @Environment(LiveWorkoutWatchBridge.self) private var watchBridge

    let plan: ParsedWorkoutPlan
    let onStarted: (PersistentIdentifier) -> Void
    let onCancel: () -> Void

    @State private var workoutTitle: String
    @State private var catalog: [ExerciseCatalog] = []
    @State private var aliasIndex: [String: ExerciseCatalog] = [:]
    @State private var overrides: [String: ExerciseCatalog] = [:]
    @State private var pickerExerciseTitle: String?
    @State private var errorMessage: String?

    init(
        plan: ParsedWorkoutPlan,
        onStarted: @escaping (PersistentIdentifier) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.plan = plan
        self.onStarted = onStarted
        self.onCancel = onCancel
        _workoutTitle = State(initialValue: plan.title)
    }

    private var store: LiveWorkoutStore {
        LiveWorkoutStore(context: modelContext)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Workout title", text: $workoutTitle)
                }

                if !plan.skippedLines.isEmpty {
                    Section {
                        Text("\(plan.skippedLines.count) line(s) could not be parsed and were skipped.")
                            .font(.footnote)
                            .foregroundStyle(Color("Warning"))
                    }
                }

                Section("Exercises") {
                    ForEach(plan.exercises, id: \.exerciseTitle) { exercise in
                        exerciseRow(exercise)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(screenBackground.ignoresSafeArea())
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Workout") { startWorkout() }
                        .disabled(workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: pickerPresented) {
                if let title = pickerExerciseTitle {
                    ExercisePickerView { selected in
                        overrides[title] = selected
                        pickerExerciseTitle = nil
                    }
                }
            }
            .task {
                _ = try? ExerciseCatalogSeeder.seedIfNeeded(in: modelContext)
                catalog = (try? modelContext.fetch(FetchDescriptor<ExerciseCatalog>())) ?? []
                aliasIndex = ExerciseCatalogMatcher.buildAliasIndex(catalog: catalog)
            }
        }
    }

    @ViewBuilder
    private func exerciseRow(_ exercise: ParsedExercise) -> some View {
        let match = resolvedMatch(for: exercise.exerciseTitle)
        let catalogEntry = overrides[exercise.exerciseTitle] ?? match.entry

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exerciseTitle)
                        .font(.headline)
                    if let canonical = catalogEntry?.canonicalName,
                       canonical != exercise.exerciseTitle {
                        Text(canonical)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                matchBadge(flag: overrides[exercise.exerciseTitle] != nil ? .matched : match.flag)
            }

            Text(setSummary(for: exercise))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let restSummary = restSummary(for: exercise) {
                Text(restSummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let noteSummary = prescriptionNoteSummary(for: exercise) {
                Text(noteSummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if overrides[exercise.exerciseTitle] != nil || match.flag == .unmatched {
                Button("Change exercise") {
                    pickerExerciseTitle = exercise.exerciseTitle
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }

    private func resolvedMatch(for exerciseTitle: String) -> CatalogMatchResult {
        if let override = overrides[exerciseTitle] {
            return CatalogMatchResult(entry: override, flag: .matched, confidence: 1)
        }
        let matchTitle = ParsedWorkoutTitle.catalogMatchTitle(from: exerciseTitle)
        return ExerciseCatalogMatcher.match(
            importedTitle: matchTitle,
            catalog: catalog,
            aliasIndex: aliasIndex
        )
    }

    @ViewBuilder
    private func matchBadge(flag: CatalogMatchFlag) -> some View {
        let (label, color): (String, Color) = switch flag {
        case .matched: ("Matched", .green)
        case .lowConfidence: ("Review", Color("Warning"))
        case .unmatched: ("Unmatched", .red)
        }

        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func setSummary(for exercise: ParsedExercise) -> String {
        let parts = exercise.sets.map { set -> String in
            let weight = set.weightKg.map { String(format: "%.0f kg", $0) } ?? "—"
            let reps = set.reps.map(String.init) ?? "—"
            var line = "\(weight) × \(reps)"
            if set.isWarmup { line += " warmup" }
            if let rpe = set.rpe { line += " @\(formatRPE(rpe))" }
            return line
        }
        return "\(exercise.sets.count) sets · \(parts.joined(separator: ", "))"
    }

    private func restSummary(for exercise: ParsedExercise) -> String? {
        if let seconds = exercise.restDurationSeconds {
            return "Rest \(seconds)s"
        }
        let perSetRests = exercise.sets.compactMap(\.restDurationSeconds)
        guard !perSetRests.isEmpty else { return nil }
        let unique = Set(perSetRests)
        if unique.count == 1, let seconds = unique.first {
            return "Rest \(seconds)s"
        }
        let parts = exercise.sets.compactMap { set -> String? in
            guard let seconds = set.restDurationSeconds else { return nil }
            return "set \(set.setIndex) \(seconds)s"
        }
        return parts.isEmpty ? nil : "Rest " + parts.joined(separator: ", ")
    }

    private func prescriptionNoteSummary(for exercise: ParsedExercise) -> String? {
        let notes = exercise.sets.compactMap(\.prescriptionNote)
        guard !notes.isEmpty else { return nil }
        return notes.joined(separator: " · ")
    }

    private func formatRPE(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    private var pickerPresented: Binding<Bool> {
        Binding(
            get: { pickerExerciseTitle != nil },
            set: { isPresented in
                if !isPresented { pickerExerciseTitle = nil }
            }
        )
    }

    private func startWorkout() {
        errorMessage = nil
        let trimmedTitle = workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Workout title is required."
            return
        }

        let exercises = plan.exercises.map { exercise in
            let match = resolvedMatch(for: exercise.exerciseTitle)
            return ParsedPlanStartRequest.ParsedPlanExercise(
                exerciseTitle: exercise.exerciseTitle,
                catalogEntry: match.entry,
                sets: exercise.sets,
                restDurationSeconds: exercise.restDurationSeconds
            )
        }

        do {
            let session = try store.start(
                fromParsedPlan: ParsedPlanStartRequest(
                    title: trimmedTitle,
                    exercises: exercises
                )
            )
            coordinator.refresh()
            watchBridge.prepareLiveSession(for: session, modelContext: modelContext)
            Task {
                await watchBridge.beginWatchWorkout(for: session, modelContext: modelContext)
            }
            onStarted(session.persistentModelID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
