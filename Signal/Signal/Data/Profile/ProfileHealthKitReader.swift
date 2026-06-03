import Foundation
import HealthKit
import os
import SwiftData

struct ProfileHealthSnapshot: Sendable, Equatable {
    var bodyMassKg: Double?
    var bodyMassMeasuredAt: Date?
    var dateOfBirth: Date?
    var biologicalSexStorage: String?
    var sources: Set<ProfileHealthSource> = []

    var hasAnyData: Bool {
        bodyMassKg != nil || dateOfBirth != nil || biologicalSexStorage != nil
    }
}

enum ProfileHealthSource: String, Sendable {
    case healthKitLive
    case dailyMetricCache
}

enum ProfileHealthKitReader {
    static let recentBodyMassMaxAge: TimeInterval = 30 * 24 * 60 * 60

    @MainActor
    static func fetchSnapshot(
        healthStore: HKHealthStore,
        accessState: HealthKitAccessState,
        modelContext: ModelContext
    ) async -> ProfileHealthSnapshot {
        var snapshot = ProfileHealthSnapshot()

        if accessState == .ready {
            if let live = await fetchLatestBodyMass(healthStore: healthStore) {
                snapshot.bodyMassKg = live.kg
                snapshot.bodyMassMeasuredAt = live.measuredAt
                snapshot.sources.insert(.healthKitLive)
            }
            mergeCharacteristics(into: &snapshot, healthStore: healthStore)
        }

        if snapshot.bodyMassKg == nil, let cached = latestBodyMassFromDailyMetrics(in: modelContext) {
            snapshot.bodyMassKg = cached.kg
            snapshot.bodyMassMeasuredAt = cached.measuredAt
            snapshot.sources.insert(.dailyMetricCache)
        }

        return snapshot
    }

    static func isRecentBodyMass(measuredAt: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(measuredAt) <= recentBodyMassMaxAge
    }

    @MainActor
    static func latestBodyMassFromDailyMetrics(
        in context: ModelContext
    ) -> (kg: Double, measuredAt: Date)? {
        var descriptor = FetchDescriptor<DailyMetric>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 120
        guard let metrics = try? context.fetch(descriptor) else { return nil }
        for metric in metrics {
            guard let kg = metric.bodyMassKg, kg > 0 else { continue }
            return (kg, metric.date)
        }
        return nil
    }

    private static func fetchLatestBodyMass(
        healthStore: HKHealthStore
    ) async -> (kg: Double, measuredAt: Date)? {
        let type = HKQuantityType(.bodyMass)
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    if !HealthKitQueryErrors.isNoData(error) {
                        Log.healthkit.error(
                            "profile body mass query failed: \(String(describing: error), privacy: .public)"
                        )
                    }
                    continuation.resume(returning: nil)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                guard kg.isFinite, kg > 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (kg, sample.endDate))
            }
            healthStore.execute(query)
        }
    }

    private static func mergeCharacteristics(
        into snapshot: inout ProfileHealthSnapshot,
        healthStore: HKHealthStore
    ) {
        do {
            let components = try healthStore.dateOfBirthComponents()
            if let date = Calendar.current.date(from: components) {
                snapshot.dateOfBirth = date
                snapshot.sources.insert(.healthKitLive)
            }
        } catch {
            Log.healthkit.debug(
                "profile date of birth unavailable: \(String(describing: error), privacy: .public)"
            )
        }

        do {
            let sexObject = try healthStore.biologicalSex()
            if let storage = biologicalSexStorage(from: sexObject.biologicalSex) {
                snapshot.biologicalSexStorage = storage
                snapshot.sources.insert(.healthKitLive)
            }
        } catch {
            Log.healthkit.debug(
                "profile biological sex unavailable: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private static func biologicalSexStorage(from sex: HKBiologicalSex) -> String? {
        switch sex {
        case .female:
            return "female"
        case .male:
            return "male"
        case .other:
            return "other"
        case .notSet:
            return nil
        @unknown default:
            return nil
        }
    }
}
