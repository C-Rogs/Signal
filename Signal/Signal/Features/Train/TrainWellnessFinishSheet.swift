import os
import SwiftData
import SwiftUI

struct TrainWellnessFinishSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LiveWorkoutCoordinator.self) private var coordinator

    let session: WorkoutSession
    let healthKitManager: HealthKitManager

    @State private var healthKitWriteNote: String?

    private var store: LiveWorkoutStore {
        LiveWorkoutStore(context: modelContext)
    }

    var body: some View {
        WellnessCaptureView(
            muscles: coordinator.pendingWellnessMuscles,
            needsSessionEffort: !WorkoutEffortScoreCalculator.hasWorkingSetRPE(in: session),
            onSave: { energy, mood, stress, soreness, notes, perceivedEffort in
                Task {
                    await completeFinishedWorkout(
                        session: session,
                        perceivedEffort: perceivedEffort,
                        saveWellness: true,
                        energy: energy,
                        mood: mood,
                        stress: stress,
                        soreness: soreness,
                        notes: notes
                    )
                    coordinator.dismissWellness()
                }
            },
            onSkip: { perceivedEffort in
                Task {
                    await completeFinishedWorkout(
                        session: session,
                        perceivedEffort: perceivedEffort,
                        saveWellness: false
                    )
                    coordinator.dismissWellness()
                }
            }
        )
        .safeAreaInset(edge: .bottom) {
            if let healthKitWriteNote {
                Text(healthKitWriteNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color("Surface"))
            }
        }
    }

    private func completeFinishedWorkout(
        session: WorkoutSession,
        perceivedEffort: Double?,
        saveWellness: Bool,
        energy: Int = 3,
        mood: Int = 3,
        stress: Int = 3,
        soreness: [String: Int] = [:],
        notes: String? = nil
    ) async {
        ExerciseProgressStore.recordFinishedSession(session, in: modelContext)

        if saveWellness {
            do {
                let entry = try store.saveWellness(
                    for: session,
                    energy: energy,
                    mood: mood,
                    stress: stress,
                    sorenessByMuscleRaw: soreness,
                    notes: notes
                )
                let vectorStore = SwiftDataVectorStore(context: modelContext)
                let embedding = EmbeddingBackend.makeService()
                await WellnessNoteIndexer.indexNotesIfNeeded(
                    entry: entry,
                    store: vectorStore,
                    service: embedding
                )
            } catch {
                Log.workout.error(
                    "wellness save failed: \(String(describing: error), privacy: .public)"
                )
            }
        }

        let effortScore = resolvedEffortScore(for: session, perceivedEffort: perceivedEffort)
        let outcome = await healthKitManager.writeFinishedWorkout(
            sessionID: session.persistentModelID,
            effortScore: effortScore,
            modelContext: modelContext
        )
        healthKitWriteNote = HealthKitWorkoutWriter.userFacingNote(for: outcome)
        coordinator.publishHealthKitWriteNote(healthKitWriteNote)

        NotificationCenter.default.post(
            name: .workoutDidFinish,
            object: nil,
            userInfo: [
                "sessionID": session.persistentModelID,
                "modelContainer": modelContext.container,
            ]
        )
    }

    private func resolvedEffortScore(for session: WorkoutSession, perceivedEffort: Double?) -> Double? {
        if let fromSets = WorkoutEffortScoreCalculator.meanScore(for: session) {
            return fromSets
        }
        if let perceivedEffort {
            return WorkoutEffortScoreCalculator.clampAndRound(perceivedEffort)
        }
        return nil
    }
}
