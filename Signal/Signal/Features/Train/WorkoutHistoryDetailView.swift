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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sessionSummaryCard

                if exercises.isEmpty {
                    ContentUnavailableView {
                        Label("No exercises", systemImage: "figure.strengthtraining.traditional")
                    } description: {
                        Text("No exercises were recorded for this workout.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    ForEach(exercises, id: \.persistentModelID) { exercise in
                        exerciseSection(exercise)
                    }
                }
            }
            .padding(TrainChrome.horizontalPadding)
            .padding(.vertical, 8)
        }
        .background(screenBackground.ignoresSafeArea())
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.persistentModelID) {
            loadExercises()
            loadHeartRateData()
        }
    }

    private var screenBackground: Color {
        TrainChrome.screenBackground(colorScheme: colorScheme)
    }

    @ViewBuilder
    private var sessionSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let end = session.endTime {
                summaryRow(label: "Ended", value: end.formatted(date: .abbreviated, time: .shortened))
            }
            if let meanRPE = sessionMeanWorkingSetRPE {
                summaryRow(
                    label: "Avg RPE",
                    value: WorkoutHistoryDetailFormatting.meanRPELabel(for: meanRPE),
                    emphasize: true
                )
            }
        }
        .padding(14)
        .trainSurfaceCard(cornerRadius: 12)
    }

    private func summaryRow(label: String, value: String, emphasize: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.metadataCaption)
                .foregroundStyle(Color("TextSecondary"))
            Spacer()
            Text(value)
                .font(emphasize ? .body.weight(.semibold).monospacedDigit() : .body.monospacedDigit())
                .foregroundStyle(emphasize ? Color("Primary") : Color("TextPrimary"))
        }
    }

    @ViewBuilder
    private func exerciseSection(_ exercise: WorkoutExercise) -> some View {
        let sets = exercise.sets.sorted { $0.setIndex < $1.setIndex }

        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: TrainRoute.exerciseDetail(.from(exercise: exercise))) {
                HStack {
                    Text(exercise.exerciseTitle)
                        .font(.headline)
                        .foregroundStyle(Color("TextPrimary"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color("TextSecondary"))
                }
            }
            .buttonStyle(.plain)

            if sets.isEmpty {
                Text("No sets logged")
                    .font(.body)
                    .foregroundStyle(Color("TextSecondary"))
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(sets.enumerated()), id: \.element.persistentModelID) { index, set in
                        setRow(set, exercise: exercise, nextSet: index + 1 < sets.count ? sets[index + 1] : nil)
                    }
                }
            }
        }
        .padding(14)
        .trainSurfaceCard(cornerRadius: 12)
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
    private func setRow(
        _ set: SetEntry,
        exercise: WorkoutExercise,
        nextSet: SetEntry?
    ) -> some View {
        let setType = WorkoutSetType(storageValue: set.setType) ?? .normal
        let isWorkingSet = setType != .warmup
        let workHR = workHeartRateBySetEntryID[set.entryID]
        let restHR = nextSet.flatMap { restHeartRateByNextSetEntryID[$0.entryID] }

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Set \(set.setIndex + 1)")
                    .font(.metadataCaption.weight(.semibold))
                    .foregroundStyle(Color("TextSecondary"))
                    .frame(width: 44, alignment: .leading)

                Text(loadLine(for: set, exercise: exercise, setType: setType))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color("TextPrimary"))
                    .frame(maxWidth: .infinity, alignment: .trailing)

                if isWorkingSet, let workHR {
                    Text(SetHeartRateDisplay.workingSetLabel(avgBPM: workHR.avgBPM))
                        .font(.metadataCaption.monospacedDigit())
                        .foregroundStyle(SetHeartRateDisplay.bpmColor(for: workHR.avgBPM))
                }
            }

            if isWorkingSet, let restHR {
                Text(SetHeartRateDisplay.restLabel(avgBPM: restHR.avgBPM))
                    .font(.metadataCaption)
                    .foregroundStyle(Color("TextSecondary"))
                    .padding(.leading, 44)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadLine(for set: SetEntry, exercise: WorkoutExercise, setType: WorkoutSetType) -> String {
        switch ExerciseLoggingMode.from(catalogEntry: exercise.catalogEntry) {
        case .strength:
            WorkoutHistoryDetailFormatting.strengthLoadLine(
                weightLabel: formatter.formatMassKg(set.weightKg),
                reps: set.reps,
                rpe: set.rpe,
                setType: setType
            )
        case .cardio:
            WorkoutHistoryDetailFormatting.cardioLoadLine(
                distanceLabel: formatter.formatDistanceKm(set.distanceKm),
                durationLabel: formatDuration(set.durationSeconds),
                rpe: set.rpe,
                setType: setType
            )
        }
    }

    private func formatDuration(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
