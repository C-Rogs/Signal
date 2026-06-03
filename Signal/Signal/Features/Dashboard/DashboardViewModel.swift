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
    var recoveryScore = RecoveryScore(
        value: 50,
        hrvClassification: .insufficientData,
        hrvAnalysis: nil,
        rhrDelta: nil,
        sleepDelta: nil,
        confidence: .low,
        breakdown: RecoveryScoreBreakdown(hrvTerm: 0, rhrTerm: 0, sleepTerm: 0, total: 50),
        todayHRV: nil,
        todayRestingHR: nil
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
        recoveryScore = RecoveryScoreCalculator.compute(
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
        headlineMetric(from: hrvPoints, snapshotValue: \.hrvSDNN).value
    }

    var hrvHeadlineLabel: String {
        headlineMetric(from: hrvPoints, snapshotValue: \.hrvSDNN).label
    }

    var latestRestingHR: Double? {
        headlineMetric(from: restingHRPoints, snapshotValue: \.restingHR).value
    }

    var restingHRHeadlineLabel: String {
        headlineMetric(from: restingHRPoints, snapshotValue: \.restingHR).label
    }

    var latestActiveEnergy: Double? {
        headlineMetric(from: activeEnergyPoints, snapshotValue: \.activeEnergy).value
    }

    var activeEnergyHeadlineLabel: String {
        headlineMetric(from: activeEnergyPoints, snapshotValue: \.activeEnergy).label
    }

    var latestSleep: Double? {
        headlineMetric(from: sleepPoints, snapshotValue: \.sleepHours).value
    }

    var sleepHeadlineLabel: String {
        headlineMetric(from: sleepPoints, snapshotValue: \.sleepHours).label
    }

    var latestBodyMass: Double? {
        DashboardSeriesBuilder.valueOnReferenceDay(
            in: bodyMassPoints,
            referenceDay: referenceDay,
            calendar: calendar
        ) ?? DashboardSeriesBuilder.latestValue(in: bodyMassPoints)
    }

    var latestSteps: Double? {
        headlineMetric(from: stepPoints, snapshotValue: \.stepCount).value
    }

    var stepsHeadlineLabel: String {
        headlineMetric(from: stepPoints, snapshotValue: \.stepCount).label
    }

    var latestExerciseMinutes: Double? {
        headlineMetric(from: exercisePoints, snapshotValue: \.appleExerciseMinutes).value
    }

    var exerciseMinutesHeadlineLabel: String {
        headlineMetric(from: exercisePoints, snapshotValue: \.appleExerciseMinutes).label
    }

    var stepsSubtitle: String {
        "\(stepsHeadlineLabel) · daily step total from Health"
    }

    var exerciseMinutesSubtitle: String {
        "\(exerciseMinutesHeadlineLabel) · Apple Exercise ring minutes"
    }

    private func headlineMetric(
        from points: [DashboardChartPoint],
        snapshotValue: (DailyMetricSnapshot) -> Double?
    ) -> (value: Double?, label: String) {
        if let today = DashboardSeriesBuilder.valueOnReferenceDay(
            in: points,
            referenceDay: referenceDay,
            calendar: calendar
        ) {
            return (today, "Today")
        }

        let sorted = metricSnapshots
            .filter { calendar.startOfDay(for: $0.date) <= referenceDay }
            .sorted { $0.date > $1.date }
        if let recent = sorted.first(where: { snapshotValue($0) != nil }),
           let value = snapshotValue(recent)
        {
            if calendar.isDateInToday(recent.date) {
                return (value, "Today")
            }
            let label = recent.date.formatted(.dateTime.month(.abbreviated).day())
            return (value, label)
        }

        return (nil, "")
    }

    var hrvChartRange: ClosedRange<Double>? {
        let values = hrvPoints.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else { return nil }
        return minValue...maxValue
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
