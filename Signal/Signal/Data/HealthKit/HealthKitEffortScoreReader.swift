import Foundation
import HealthKit
import os

enum HealthKitEffortScoreReader {
    static func effortScore(sampleUUIDString: String?, healthStore: HKHealthStore = HKHealthStore()) async -> Double? {
        guard HKHealthStore.isHealthDataAvailable(),
              let sampleUUIDString,
              let uuid = UUID(uuidString: sampleUUIDString)
        else { return nil }

        do {
            guard let sample = try await fetchSample(uuid: uuid, healthStore: healthStore) as? HKQuantitySample else {
                return nil
            }
            let value = sample.quantity.doubleValue(for: .appleEffortScore())
            return WorkoutEffortScoreCalculator.clampAndRound(value)
        } catch {
            Log.healthkit.error(
                "workoutEffortScore read failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    static func enrichedWorkoutDaySessions(
        from sessions: [WorkoutSession],
        calendar: Calendar,
        healthStore: HKHealthStore = HKHealthStore()
    ) async -> [WorkoutDaySession] {
        var daySessions = ExertionScoreCalculator.workoutDaySessions(from: sessions, calendar: calendar)
        guard HKHealthStore.isHealthDataAvailable() else { return daySessions }

        for index in daySessions.indices where daySessions[index].meanRPE == nil {
            guard let session = sessions.first(where: { workout in
                workout.endTime != nil
                    && calendar.isDate(workout.date, inSameDayAs: daySessions[index].date)
                    && ExertionScoreCalculator.workoutDaySessions(from: [workout], calendar: calendar)
                        .first?.workingSetCount == daySessions[index].workingSetCount
            }) ?? sessions.first(where: { workout in
                workout.endTime != nil
                    && calendar.isDate(workout.date, inSameDayAs: daySessions[index].date)
            }) else { continue }

            guard let effort = await effortScore(
                sampleUUIDString: session.healthKitEffortSampleUUID,
                healthStore: healthStore
            ) else { continue }

            daySessions[index] = WorkoutDaySession(
                date: daySessions[index].date,
                workingSetCount: daySessions[index].workingSetCount,
                meanRPE: nil,
                hkEffortScore: effort
            )
        }
        return daySessions
    }

    private static func fetchSample(uuid: UUID, healthStore: HKHealthStore) async throws -> HKSample? {
        let predicate = HKQuery.predicateForObject(with: uuid)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.workoutEffortScore),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.first)
            }
            healthStore.execute(query)
        }
    }
}
