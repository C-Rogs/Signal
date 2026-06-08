import Foundation
import SwiftData
import os

enum DataQualityMigration {
    static let userDefaultsKey = "dataQualityMigrationV1Done"

    @MainActor
    static func scheduleIfNeeded(modelContainer: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: userDefaultsKey) else { return }
        Task { @MainActor in
            await Task.yield()
            runIfNeeded(modelContainer: modelContainer)
        }
    }

    @MainActor
    static func runIfNeeded(modelContainer: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: userDefaultsKey) else { return }
        let context = ModelContext(modelContainer)
        do {
            let metrics = try context.fetch(FetchDescriptor<DailyMetric>())
            var corrected = 0
            for metric in metrics {
                guard let spo2 = metric.bloodOxygenPct else { continue }
                let validation = DataQualityValidator.validateSpO2(spo2)
                guard let correctedValue = validation.correctedValue else { continue }
                let metricDate = metric.date
                var descriptor = FetchDescriptor<DataQualityFlag>(
                    predicate: #Predicate { flag in
                        flag.date == metricDate && flag.metricKind == "bloodOxygenPct"
                    }
                )
                descriptor.fetchLimit = 1
                if try context.fetch(descriptor).isEmpty {
                    context.insert(
                        DataQualityFlag(
                            date: metric.date,
                            metricKind: DataQualityValidator.spo2MetricKind,
                            originalValue: spo2,
                            issue: DataQualityIssue.corrected.rawValue,
                            wasCorrected: true
                        )
                    )
                }
                metric.bloodOxygenPct = correctedValue
                corrected += 1
            }
            if corrected > 0 {
                try context.save()
            }
            UserDefaults.standard.set(true, forKey: userDefaultsKey)
            Log.sync.info(
                "data quality migration v1 complete correctedSpO2=\(corrected, privacy: .public)"
            )
        } catch {
            Log.sync.error(
                "data quality migration v1 failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
