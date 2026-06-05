import SwiftData
import SwiftUI

struct WorkoutHistoryDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(UnitPreferences.self) private var unitPreferences

    let session: WorkoutSession

    @State private var exercises: [WorkoutExercise] = []
    @State private var workHeartRateBySetEntryID: [UUID: SetHeartRateData] = [:]
    @State private var restHeartRateByNextSetEntryID: [UUID: SetHeartRateData] = [:]

    private var formatter: DisplayUnitFormatter {
        DisplayUnitFormatter(preferences: unitPreferences)
    }

    private var sessionMeanWorkingSetRPE: Double? {
        WorkoutHistoryDetailFormatting.meanWorkingSetRPE(
            sets: exercises.flatMap(\.sets)
        )
    }

    var body: some View {
        List {
            if let end = session.endTime {
                LabeledContent("Ended", value: end.formatted(date: .abbreviated, time: .shortened))
            }
            if let meanRPE = sessionMeanWorkingSetRPE {
                LabeledContent(
                    "Avg RPE",
                    value: WorkoutHistoryDetailFormatting.meanRPELabel(for: meanRPE)
                )
            }
            if exercises.isEmpty {
                Section {
                    Text("No exercises recorded")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(exercises, id: \.persistentModelID) { exercise in
                    Section {
                        let sets = exercise.sets.sorted { $0.setIndex < $1.setIndex }
                        if sets.isEmpty {
                            Text("No sets logged")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        } else {
                            ForEach(Array(sets.enumerated()), id: \.element.persistentModelID) { index, set in
                                setSummary(set, exercise: exercise, nextSet: index + 1 < sets.count ? sets[index + 1] : nil)
                            }
                        }
                    } header: {
                        NavigationLink(value: TrainRoute.exerciseDetail(.from(exercise: exercise))) {
                            Text(exercise.exerciseTitle)
                                .font(.headline)
                                .foregroundStyle(Color("TextPrimary"))
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
            loadHeartRateData()
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

    @MainActor
    private func loadHeartRateData() {
        let sessionUUID = session.resolvedSessionID(in: modelContext)
        let rows = (try? SetHeartRateDataStore.fetch(sessionID: sessionUUID, in: modelContext)) ?? []
        var work: [UUID: SetHeartRateData] = [:]
        var rest: [UUID: SetHeartRateData] = [:]
        for row in rows {
            if row.isRestInterval {
                rest[row.setEntryID] = row
            } else {
                work[row.setEntryID] = row
            }
        }
        workHeartRateBySetEntryID = work
        restHeartRateByNextSetEntryID = rest
    }

    @ViewBuilder
    private func setSummary(
        _ set: SetEntry,
        exercise: WorkoutExercise,
        nextSet: SetEntry?
    ) -> some View {
        let setType = WorkoutSetType(storageValue: set.setType) ?? .normal
        let isWorkingSet = setType != .warmup
        let workHR = workHeartRateBySetEntryID[set.entryID]
        let restHR = nextSet.flatMap { restHeartRateByNextSetEntryID[$0.entryID] }

        VStack(alignment: .leading, spacing: 4) {
            switch ExerciseLoggingMode.from(catalogEntry: exercise.catalogEntry) {
            case .strength:
                HStack {
                    Text("Set \(set.setIndex + 1)")
                    Spacer()
                    Text(
                        WorkoutHistoryDetailFormatting.strengthLoadLine(
                            weightLabel: formatter.formatMassKg(set.weightKg),
                            reps: set.reps,
                            rpe: set.rpe,
                            setType: setType
                        )
                    )
                    .foregroundStyle(.secondary)
                    if isWorkingSet, let workHR {
                        Text(SetHeartRateDisplay.workingSetLabel(avgBPM: workHR.avgBPM))
                            .font(.subheadline)
                            .foregroundStyle(SetHeartRateDisplay.bpmColor(for: workHR.avgBPM))
                    }
                }
            case .cardio:
                HStack {
                    Text("Set \(set.setIndex + 1)")
                    Spacer()
                    Text(
                        WorkoutHistoryDetailFormatting.cardioLoadLine(
                            distanceLabel: formatter.formatDistanceKm(set.distanceKm),
                            durationLabel: formatDuration(set.durationSeconds),
                            rpe: set.rpe,
                            setType: setType
                        )
                    )
                    .foregroundStyle(.secondary)
                    if isWorkingSet, let workHR {
                        Text(SetHeartRateDisplay.workingSetLabel(avgBPM: workHR.avgBPM))
                            .font(.subheadline)
                            .foregroundStyle(SetHeartRateDisplay.bpmColor(for: workHR.avgBPM))
                    }
                }
            }

            if isWorkingSet, let restHR {
                Text(SetHeartRateDisplay.restLabel(avgBPM: restHR.avgBPM))
                    .font(.caption)
                    .foregroundStyle(Color("TextSecondary"))
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
