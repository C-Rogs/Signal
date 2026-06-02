import Foundation
import Observation
import os

struct DailyNutritionSnapshot: Sendable, Equatable {
    let date: Date
    let dietaryEnergyKcal: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatTotalG: Double?
}

@MainActor
@Observable
final class DashboardViewModel {
    var selectedWindow: RecoveryWindow = .thirty
    var rollingMeans = MetricRollingMeans(
        sevenDay: WindowMean(hrvSDNN: nil, restingHR: nil, sampleDays: 0),
        thirtyDay: WindowMean(hrvSDNN: nil, restingHR: nil, sampleDays: 0),
        sixtyDay: WindowMean(hrvSDNN: nil, restingHR: nil, sampleDays: 0)
    )
    var recoveryIndicator = RecoveryIndicator(
        score: nil,
        status: .unknown,
        todayHRV: nil,
        todayRestingHR: nil,
        baselineHRV: nil,
        baselineRestingHR: nil
    )
    var hrvPoints: [DashboardChartPoint] = []
    var restingHRPoints: [DashboardChartPoint] = []
    var activeEnergyPoints: [DashboardChartPoint] = []
    var sleepPoints: [DashboardChartPoint] = []
    var bodyMassPoints: [DashboardChartPoint] = []
    var stepPoints: [DashboardChartPoint] = []
    var exercisePoints: [DashboardChartPoint] = []
    var nutritionEnergyPoints: [DashboardChartPoint] = []
    var latestNutrition: DailyNutritionSnapshot?

    private var metricSnapshots: [DailyMetricSnapshot] = []
    private var nutritionSnapshots: [DailyNutritionSnapshot] = []
    private let calendar: Calendar
    private let referenceDay: Date

    init(calendar: Calendar? = nil, referenceDay: Date = Date()) {
        if let calendar {
            self.calendar = calendar
        } else {
            var defaultCalendar = Calendar(identifier: .gregorian)
            defaultCalendar.timeZone = .current
            self.calendar = defaultCalendar
        }
        self.referenceDay = self.calendar.startOfDay(for: referenceDay)
    }

    func reload(metrics: [DailyMetric], nutrition: [DailyNutrition]) {
        metricSnapshots = metrics.map(DailyMetricSnapshot.init(metric:))
        nutritionSnapshots = nutrition.map {
            DailyNutritionSnapshot(
                date: $0.date,
                dietaryEnergyKcal: $0.dietaryEnergyKcal,
                proteinG: $0.proteinG,
                carbsG: $0.carbsG,
                fatTotalG: $0.fatTotalG
            )
        }
        recompute()
        Log.ui.info(
            "dashboard reloaded metrics=\(self.metricSnapshots.count, privacy: .public) nutrition=\(self.nutritionSnapshots.count, privacy: .public) window=\(self.selectedWindow.rawValue, privacy: .public)"
        )
    }

    func recomputeSeriesForSelectedWindow() {
        recomputeSeries()
        Log.ui.info(
            "dashboard window=\(self.selectedWindow.rawValue, privacy: .public) hrvPoints=\(self.hrvPoints.count, privacy: .public)"
        )
    }

    private func recompute() {
        rollingMeans = RecoveryEngine.rollingMeans(
            metrics: metricSnapshots,
            referenceDay: referenceDay,
            calendar: calendar
        )
        recoveryIndicator = RecoveryEngine.recoveryIndicator(
            metrics: metricSnapshots,
            referenceDay: referenceDay,
            calendar: calendar
        )
        recomputeSeries()
    }

    private func recomputeSeries() {
        let days = selectedWindow.rawValue
        hrvPoints = DashboardSeriesBuilder.points(
            from: metricSnapshots,
            days: days,
            referenceDay: referenceDay,
            calendar: calendar,
            value: \.hrvSDNN
        )
        restingHRPoints = DashboardSeriesBuilder.points(
            from: metricSnapshots,
            days: days,
            referenceDay: referenceDay,
            calendar: calendar,
            value: \.restingHR
        )
        activeEnergyPoints = DashboardSeriesBuilder.points(
            from: metricSnapshots,
            days: days,
            referenceDay: referenceDay,
            calendar: calendar,
            value: \.activeEnergy
        )
        sleepPoints = DashboardSeriesBuilder.points(
            from: metricSnapshots,
            days: days,
            referenceDay: referenceDay,
            calendar: calendar,
            value: \.sleepHours
        )
        bodyMassPoints = DashboardSeriesBuilder.points(
            from: metricSnapshots,
            days: days,
            referenceDay: referenceDay,
            calendar: calendar,
            value: \.bodyMassKg
        )
        stepPoints = DashboardSeriesBuilder.points(
            from: metricSnapshots,
            days: days,
            referenceDay: referenceDay,
            calendar: calendar,
            value: \.stepCount
        )
        exercisePoints = DashboardSeriesBuilder.points(
            from: metricSnapshots,
            days: days,
            referenceDay: referenceDay,
            calendar: calendar,
            value: \.appleExerciseMinutes
        )
        nutritionEnergyPoints = DashboardSeriesBuilder.points(
            from: nutritionSnapshots.map { snap in
                DailyMetricSnapshot(
                    date: snap.date,
                    hrvSDNN: nil,
                    restingHR: nil,
                    activeEnergy: snap.dietaryEnergyKcal,
                    sleepHours: nil,
                    bodyMassKg: nil,
                    stepCount: nil,
                    appleExerciseMinutes: nil
                )
            },
            days: days,
            referenceDay: referenceDay,
            calendar: calendar,
            value: \.activeEnergy
        )
        latestNutrition = nutritionSnapshots
            .filter { calendar.startOfDay(for: $0.date) <= referenceDay }
            .sorted { $0.date > $1.date }
            .first { $0.dietaryEnergyKcal != nil || $0.proteinG != nil }
    }

    var latestHRV: Double? {
        DashboardSeriesBuilder.latestValue(in: hrvPoints)
    }

    var latestRestingHR: Double? {
        DashboardSeriesBuilder.latestValue(in: restingHRPoints)
    }

    var latestActiveEnergy: Double? {
        DashboardSeriesBuilder.latestValue(in: activeEnergyPoints)
    }

    var latestSleep: Double? {
        DashboardSeriesBuilder.latestValue(in: sleepPoints)
    }

    var latestBodyMass: Double? {
        DashboardSeriesBuilder.latestValue(in: bodyMassPoints)
    }

    var latestSteps: Double? {
        DashboardSeriesBuilder.latestValue(in: stepPoints)
    }

    var latestExerciseMinutes: Double? {
        DashboardSeriesBuilder.latestValue(in: exercisePoints)
    }

    var activitySubtitle: String {
        let steps = DashboardFormatting.steps(latestSteps)
        let exercise = DashboardFormatting.minutes(latestExerciseMinutes)
        return "\(steps) steps · \(exercise) exercise"
    }

    var nutritionSubtitle: String? {
        guard let latestNutrition else { return nil }
        var parts: [String] = []
        if let energy = latestNutrition.dietaryEnergyKcal {
            parts.append(DashboardFormatting.calories(energy))
        }
        if let protein = latestNutrition.proteinG {
            parts.append(DashboardFormatting.protein(protein))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }
}
