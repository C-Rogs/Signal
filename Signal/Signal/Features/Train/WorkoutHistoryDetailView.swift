import SwiftData
import SwiftUI

struct WorkoutHistoryDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(UnitPreferences.self) private var unitPreferences

    let session: WorkoutSession

    @State private var exercises: [WorkoutExercise] = []

    private var formatter: DisplayUnitFormatter {
        DisplayUnitFormatter(preferences: unitPreferences)
    }

    var body: some View {
        List {
            if let end = session.endTime {
                LabeledContent("Ended", value: end.formatted(date: .abbreviated, time: .shortened))
            }
            if exercises.isEmpty {
                Section {
                    Text("No exercises recorded")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(exercises, id: \.persistentModelID) { exercise in
                    Section(exercise.exerciseTitle) {
                        let sets = exercise.sets.sorted { $0.setIndex < $1.setIndex }
                        if sets.isEmpty {
                            Text("No sets logged")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        } else {
                            ForEach(sets, id: \.persistentModelID) { set in
                                setSummary(set, exercise: exercise)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(screenBackground.ignoresSafeArea())
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.persistentModelID) {
            loadExercises()
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    @MainActor
    private func loadExercises() {
        let sessionID = session.persistentModelID
        let all = (try? modelContext.fetch(FetchDescriptor<WorkoutExercise>())) ?? []
        exercises = all
            .filter { $0.session?.persistentModelID == sessionID }
            .sorted { $0.order < $1.order }
    }

    @ViewBuilder
    private func setSummary(_ set: SetEntry, exercise: WorkoutExercise) -> some View {
        let mode = ExerciseLoggingMode.from(catalogEntry: exercise.catalogEntry)
        switch mode {
        case .strength:
            HStack {
                Text("Set \(set.setIndex + 1)")
                Spacer()
                Text("\(formatter.formatMassKg(set.weightKg)) × \(set.reps.map(String.init) ?? "—")")
                    .foregroundStyle(.secondary)
            }
        case .cardio:
            HStack {
                Text("Set \(set.setIndex + 1)")
                Spacer()
                Text("\(formatter.formatDistanceKm(set.distanceKm)) / \(formatDuration(set.durationSeconds))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatDuration(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
