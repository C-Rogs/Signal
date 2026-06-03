import Foundation
import SwiftData
import os

struct DerivedVolumeRow: Sendable {
    let muscleGroup: MuscleGroup
    let fractionalSets: Double
    let status: VolumeStatus
}

struct DerivedMetricsSnapshot: Sendable {
    var weeklyVolume: [DerivedVolumeRow]
    var acwr: ACWRResult?
    var recentE1RM: [(exerciseID: String, e1RMKg: Double, sessionDate: Date)]
    var proteinTarget: ProteinTarget?
    var dataQualityFlagCount: Int
}

actor DerivedMetricsService {
    static let shared = DerivedMetricsService()

    private var cachedSnapshot: DerivedMetricsSnapshot?
    private var observationTask: Task<Void, Never>?

    private init() {
        observationTask = Task { [weak self] in
            await self?.observeInvalidationNotifications()
        }
    }

    func invalidateCache() {
        cachedSnapshot = nil
    }

    func handleWorkoutDidFinish(sessionID: PersistentIdentifier, modelContainer: ModelContainer) async {
        invalidateCache()
        await MainActor.run {
            let context = ModelContext(modelContainer)
            guard let session = context.model(for: sessionID) as? WorkoutSession else { return }
            ExerciseProgressStore.recordFinishedSession(session, in: context)
        }
    }

    func currentWeekVolume(modelContainer: ModelContainer) async -> [MuscleGroup: Double] {
        await onMainContext(modelContainer) { computeCurrentWeekVolume(in: $0) }
    }

    func acwr(for muscle: MuscleGroup?, modelContainer: ModelContainer) async -> ACWRResult? {
        await onMainContext(modelContainer) { computeACWR(for: muscle, in: $0) }
    }

    func e1RMHistory(for exerciseID: String, modelContainer: ModelContainer) async -> [ExerciseE1RMHistoryRow] {
        await onMainContext(modelContainer) {
            let rows = (try? ExerciseProgressStore.fetchHistory(exerciseID: exerciseID, in: $0)) ?? []
            return rows.map {
                ExerciseE1RMHistoryRow(
                    exerciseID: $0.exerciseID,
                    sessionDate: $0.sessionDate,
                    e1RMKg: $0.e1RM_kg,
                    bestSetWeightKg: $0.bestSetWeight_kg,
                    bestSetReps: $0.bestSetReps
                )
            }
        }
    }

    func proteinTarget(modelContainer: ModelContainer) async -> ProteinTarget? {
        await onMainContext(modelContainer) { computeProteinTarget(in: $0) }
    }

    func snapshot(modelContainer: ModelContainer) async -> DerivedMetricsSnapshot {
        if let cachedSnapshot {
            return cachedSnapshot
        }
        let built = await onMainContext(modelContainer) { buildSnapshot(in: $0) }
        cachedSnapshot = built
        return built
    }

    private func onMainContext<T: Sendable>(
        _ modelContainer: ModelContainer,
        _ work: @MainActor @Sendable (ModelContext) -> T
    ) async -> T {
        await MainActor.run {
            work(ModelContext(modelContainer))
        }
    }

    private func observeInvalidationNotifications() async {
        let workoutFinish = NotificationCenter.default.notifications(
            named: Notification.Name("workoutDidFinish"),
            object: nil
        )
        let deltaFinish = NotificationCenter.default.notifications(
            named: Notification.Name("healthKitProcessDeltaDidFinish"),
            object: nil
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await notification in workoutFinish {
                    guard let sessionID = notification.userInfo?["sessionID"] as? PersistentIdentifier,
                          let container = notification.userInfo?["modelContainer"] as? ModelContainer
                    else { continue }
                    await self.handleWorkoutDidFinish(sessionID: sessionID, modelContainer: container)
                }
            }
            group.addTask {
                for await _ in deltaFinish {
                    await self.invalidateCache()
                }
            }
        }
    }

    @MainActor
    private func buildSnapshot(in context: ModelContext) -> DerivedMetricsSnapshot {
        let volumeMap = computeCurrentWeekVolume(in: context)
        let weeklyVolume = MuscleGroup.allCases.map { group in
            let sets = volumeMap[group] ?? 0
            return DerivedVolumeRow(
                muscleGroup: group,
                fractionalSets: sets,
                status: VolumeStatus.status(fractionalSets: sets, landmarks: group.landmarks)
            )
        }
        .filter { $0.fractionalSets > 0 || $0.muscleGroup.landmarks.mev > 0 }

        let recentRows = (try? ExerciseProgressStore.fetchRecentDistinctExercises(limit: 5, in: context)) ?? []
        let recentE1RM = recentRows.map { row in
            (exerciseID: row.exerciseID, e1RMKg: row.e1RM_kg, sessionDate: row.sessionDate)
        }

        let flagCount = (try? context.fetchCount(FetchDescriptor<DataQualityFlag>())) ?? 0

        return DerivedMetricsSnapshot(
            weeklyVolume: weeklyVolume,
            acwr: computeACWR(for: nil, in: context),
            recentE1RM: recentE1RM,
            proteinTarget: computeProteinTarget(in: context),
            dataQualityFlagCount: flagCount
        )
    }

    @MainActor
    private func computeCurrentWeekVolume(in context: ModelContext) -> [MuscleGroup: Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else {
            return [:]
        }

        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.endTime != nil && session.date >= weekStart
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        let sessions = (try? context.fetch(descriptor)) ?? []
        var contributions: [VolumeSetContribution] = []
        contributions.reserveCapacity(sessions.count * 4)
        for session in sessions {
            for exercise in session.exercises {
                contributions.append(contentsOf: VolumeCalculator.contributions(from: exercise))
            }
        }
        return VolumeCalculator.fractionalVolume(for: contributions)
    }

    @MainActor
    private func computeACWR(for muscle: MuscleGroup?, in context: ModelContext) -> ACWRResult? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let rangeStart = calendar.date(byAdding: .day, value: -27, to: today) else {
            return nil
        }

        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.endTime != nil && session.date >= rangeStart
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []

        var loadsByDay: [Date: Double] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.date)
            let sets: Double
            if let muscle {
                let contributions = session.exercises.flatMap { VolumeCalculator.contributions(from: $0) }
                let volume = VolumeCalculator.fractionalVolume(for: contributions)
                sets = volume[muscle] ?? 0
            } else {
                var count = 0.0
                for exercise in session.exercises {
                    for set in exercise.sets where WorkoutSetType(storageValue: set.setType) != .warmup {
                        count += 1
                    }
                }
                sets = count
            }
            loadsByDay[day, default: 0] += sets
        }

        let dailyLoads = loadsByDay.map { (date: $0.key, totalSets: Int($0.value.rounded())) }
        return ACWRCalculator.compute(dailyLoads: dailyLoads, referenceDate: today, calendar: calendar)
    }

    @MainActor
    private func computeProteinTarget(in context: ModelContext) -> ProteinTarget? {
        let profileDescriptor = FetchDescriptor<UserProfile>()
        let profile = try? context.fetch(profileDescriptor).first
        guard let bodyweight = profile?.bodyweightKg else { return nil }

        let nutritionDescriptor = FetchDescriptor<DailyNutrition>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let latestProtein = try? context.fetch(nutritionDescriptor)
            .first(where: { $0.proteinG != nil })?
            .proteinG

        return ProteinTarget(bodyweightKg: bodyweight, actualGrams: latestProtein)
    }
}
