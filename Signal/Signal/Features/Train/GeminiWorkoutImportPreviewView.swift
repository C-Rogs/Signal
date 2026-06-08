import SwiftData
import SwiftUI

struct GeminiWorkoutImportPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LiveWorkoutCoordinator.self) private var coordinator
    @Environment(LiveWorkoutWatchBridge.self) private var watchBridge

    let plan: ParsedWorkoutPlan
    let onStarted: (PersistentIdentifier) -> Void
    let onRoutineSaved: () -> Void
    let onCancel: () -> Void

    @State private var workoutTitle: String
    @State private var showSaveRoutineAlert = false
    @State private var routineName = ""
    @State private var catalog: [ExerciseCatalog] = []
    @State private var aliasIndex: [String: ExerciseCatalog] = [:]
    @State private var overrides: [String: ExerciseCatalog] = [:]
    @State private var pickerExerciseTitle: String?
    @State private var errorMessage: String?

    init(
        plan: ParsedWorkoutPlan,
        onStarted: @escaping (PersistentIdentifier) -> Void,
        onRoutineSaved: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.plan = plan
        self.onStarted = onStarted
        self.onRoutineSaved = onRoutineSaved
        self.onCancel = onCancel
        _workoutTitle = State(initialValue: plan.title)
    }

    private var store: LiveWorkoutStore {
        LiveWorkoutStore(context: modelContext)
    }

    private var templateStore: RoutineTemplateStore {
        RoutineTemplateStore(context: modelContext)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Workout title")
                            .font(.metadataCaption.weight(.semibold))
                            .foregroundStyle(Color("TextSecondary"))
                        TextField("Workout title", text: $workoutTitle)
                            .font(.body)
                            .padding(12)
                            .trainSurfaceCard(cornerRadius: 12)
                    }

                    if !plan.skippedLines.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color("Warning"))
                            Text("\(plan.skippedLines.count) line(s) could not be parsed and were skipped.")
                                .font(.metadataCaption)
                                .foregroundStyle(Color("Warning"))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .trainSurfaceCard(cornerRadius: 12)
                    }

                    TrainSectionHeader(
                        title: "Exercises",
                        trailing: "\(plan.exercises.count)"
                    )

                    VStack(spacing: 10) {
                        ForEach(plan.exercises, id: \.exerciseTitle) { exercise in
                            exerciseCard(exercise)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.metadataCaption)
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .trainSurfaceCard(cornerRadius: 12)
                    }

                    Button {
                        startWorkout()
                    } label: {
                        Text("Start Workout")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("Primary"))
                    .disabled(workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.top, 4)

                    Button {
                        routineName = workoutTitle
                        showSaveRoutineAlert = true
                    } label: {
                        Text("Save as Routine")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .disabled(workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(TrainChrome.horizontalPadding)
                .padding(.vertical, 8)
            }
            .background(screenBackground.ignoresSafeArea())
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { onCancel() }
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
            .alert("Save as Routine", isPresented: $showSaveRoutineAlert) {
                TextField("Routine name", text: $routineName)
                Button("Save") {
                    saveAsRoutine()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save this workout as a reusable routine without starting a session.")
            }
        }
    }

    @ViewBuilder
    private func exerciseCard(_ exercise: ParsedExercise) -> some View {
        let match = resolvedMatch(for: exercise.exerciseTitle)
        let catalogEntry = overrides[exercise.exerciseTitle] ?? match.entry
        let matchFlag = overrides[exercise.exerciseTitle] != nil ? CatalogMatchFlag.matched : match.flag

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exerciseTitle)
                        .font(.headline)
                        .foregroundStyle(Color("TextPrimary"))
                    if let canonical = catalogEntry?.canonicalName,
                       canonical != exercise.exerciseTitle {
                        Text(canonical)
                            .font(.metadataCaption)
                            .foregroundStyle(Color("TextSecondary"))
                    }
                }
                Spacer(minLength: 8)
                matchBadge(flag: matchFlag)
            }

            Text(setSummary(for: exercise))
                .font(.body.monospacedDigit())
                .foregroundStyle(Color("TextPrimary"))

            if let restSummary = restSummary(for: exercise) {
                Text(restSummary)
                    .font(.metadataCaption)
                    .foregroundStyle(Color("TextSecondary"))
            }

            if let noteSummary = prescriptionNoteSummary(for: exercise) {
                Text(noteSummary)
                    .font(.metadataCaption)
                    .foregroundStyle(Color("TextSecondary"))
            }

            if overrides[exercise.exerciseTitle] != nil || match.flag == .unmatched {
                Button("Change Exercise") {
                    pickerExerciseTitle = exercise.exerciseTitle
                }
                .font(.body.weight(.medium))
                .frame(minHeight: 44)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainSurfaceCard(cornerRadius: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(importAccessibilityLabel(exercise: exercise, flag: matchFlag))
    }

    private func importAccessibilityLabel(exercise: ParsedExercise, flag: CatalogMatchFlag) -> String {
        let status: String = switch flag {
        case .matched: "matched"
        case .lowConfidence: "needs review"
        case .unmatched: "unmatched"
        }
        return "\(exercise.exerciseTitle), \(status), \(setSummary(for: exercise))"
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
        let (label, style): (String, TrainStatusChipStyle) = switch flag {
        case .matched: ("Matched", .positive)
        case .lowConfidence: ("Review", .warning)
        case .unmatched: ("Unmatched", .destructive)
        }

        TrainStatusChip(title: label, style: style)
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
        TrainChrome.screenBackground(colorScheme: colorScheme)
    }

    private var pickerPresented: Binding<Bool> {
        Binding(
            get: { pickerExerciseTitle != nil },
            set: { isPresented in
                if !isPresented { pickerExerciseTitle = nil }
            }
        )
    }

    private func buildStartRequest() -> ParsedPlanStartRequest? {
        let trimmedTitle = workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let exercises = plan.exercises.map { exercise in
            let match = resolvedMatch(for: exercise.exerciseTitle)
            return ParsedPlanStartRequest.ParsedPlanExercise(
                exerciseTitle: exercise.exerciseTitle,
                catalogEntry: match.entry,
                sets: exercise.sets,
                restDurationSeconds: exercise.restDurationSeconds
            )
        }

        return ParsedPlanStartRequest(title: trimmedTitle, exercises: exercises)
    }

    private func startWorkout() {
        errorMessage = nil
        guard let request = buildStartRequest() else {
            errorMessage = "Workout title is required."
            return
        }

        do {
            let session = try store.start(fromParsedPlan: request)
            coordinator.refresh()
            TrainFeedback.shared.play(.workoutStart)
            watchBridge.prepareLiveSession(for: session, modelContext: modelContext)
            Task {
                await watchBridge.beginWatchWorkout(for: session, modelContext: modelContext)
            }
            onStarted(session.persistentModelID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAsRoutine() {
        errorMessage = nil
        let trimmedName = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Routine name is required."
            return
        }
        guard let request = buildStartRequest() else {
            errorMessage = "Workout title is required."
            return
        }

        do {
            _ = try templateStore.createRoutine(name: trimmedName, from: request)
            TrainFeedback.shared.play(.selection)
            onRoutineSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
