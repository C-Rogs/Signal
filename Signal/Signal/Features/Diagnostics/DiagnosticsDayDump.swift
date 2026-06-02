import Foundation
import SwiftData

struct DiagnosticsDayDumpTarget: Sendable, Equatable {
    let labels: [String]
    let dayKey: String
}

enum DiagnosticsDayDump {
    private static let anchorMay2026 = "2026-05-31"
    private static let anchorMarch2024 = "2024-03-19"

    static func targets(in context: ModelContext, calendar: Calendar = .current) throws -> [DiagnosticsDayDumpTarget] {
        var merged: [DiagnosticsDayDumpTarget] = []

        func append(label: String, dayKey: String) {
            if let index = merged.firstIndex(where: { $0.dayKey == dayKey }) {
                if !merged[index].labels.contains(label) {
                    merged[index] = DiagnosticsDayDumpTarget(
                        labels: merged[index].labels + [label],
                        dayKey: dayKey
                    )
                }
            } else {
                merged.append(DiagnosticsDayDumpTarget(labels: [label], dayKey: dayKey))
            }
        }

        append(label: "fixed", dayKey: anchorMay2026)
        if let nutritionDay = try latestNutritionDayKey(in: context, calendar: calendar) {
            append(label: "latest nutrition", dayKey: nutritionDay)
        } else {
            merged.append(DiagnosticsDayDumpTarget(labels: ["latest nutrition (none found)"], dayKey: ""))
        }
        append(label: "fixed", dayKey: anchorMarch2024)
        return merged
    }

    static func buildReport(
        in context: ModelContext,
        generatedAt: Date = Date(),
        calendar: Calendar = .current
    ) throws -> String {
        var lines: [String] = []
        lines.append("SIGNAL DAY DUMP — \(formattedDateTime(generatedAt))")
        lines.append("")

        for target in try targets(in: context, calendar: calendar) {
            lines.append(contentsOf: section(for: target, in: context, calendar: calendar))
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func section(
        for target: DiagnosticsDayDumpTarget,
        in context: ModelContext,
        calendar: Calendar
    ) -> [String] {
        let labelText = target.labels.joined(separator: ", ")
        var lines: [String] = []
        lines.append("=== \(target.dayKey.isEmpty ? "n/a" : target.dayKey) (\(labelText)) ===")

        guard !target.dayKey.isEmpty else {
            lines.append("No DailyNutrition row with logged macros or energy.")
            return lines
        }

        let vectors = fetchVectors(dayKey: target.dayKey, in: context)
        lines.append("--- HealthVector summaryText ---")
        if vectors.isEmpty {
            lines.append("(no HealthVector rows for this dayKey)")
        } else {
            for row in vectors {
                lines.append("metricKind=\(row.metricKind)")
                lines.append(row.summaryText)
                if vectors.count > 1 {
                    lines.append("---")
                }
            }
        }

        lines.append("--- Structured store ---")
        lines.append(formatDailyMetric(dayKey: target.dayKey, in: context, calendar: calendar))
        lines.append(formatDailyNutrition(dayKey: target.dayKey, in: context, calendar: calendar))
        lines.append(contentsOf: formatWorkouts(dayKey: target.dayKey, in: context, calendar: calendar))
        return lines
    }

    private static func fetchVectors(dayKey: String, in context: ModelContext) -> [HealthVector] {
        let key = dayKey
        let descriptor = FetchDescriptor<HealthVector>(
            predicate: #Predicate { $0.dayKey == key },
            sortBy: [SortDescriptor(\.metricKind, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func formatDailyMetric(
        dayKey: String,
        in context: ModelContext,
        calendar: Calendar
    ) -> String {
        guard let metric = dailyMetric(for: dayKey, in: context, calendar: calendar) else {
            return "DailyMetric: none"
        }
        return [
            "DailyMetric:",
            "  bodyMassKg=\(formatOptional(metric.bodyMassKg))",
            "  sleepHours=\(formatOptional(metric.sleepHours))",
            "  hrvSDNN_ms=\(formatOptional(metric.hrvSDNN_ms))",
        ].joined(separator: "\n")
    }

    private static func formatDailyNutrition(
        dayKey: String,
        in context: ModelContext,
        calendar: Calendar
    ) -> String {
        guard let row = dailyNutrition(for: dayKey, in: context, calendar: calendar) else {
            return "DailyNutrition: none"
        }
        return [
            "DailyNutrition:",
            "  dietaryEnergyKcal=\(formatOptional(row.dietaryEnergyKcal))",
            "  proteinG=\(formatOptional(row.proteinG))",
            "  carbsG=\(formatOptional(row.carbsG))",
            "  fatTotalG=\(formatOptional(row.fatTotalG))",
        ].joined(separator: "\n")
    }

    private static func formatWorkouts(
        dayKey: String,
        in context: ModelContext,
        calendar: Calendar
    ) -> [String] {
        let sessions = workoutSessions(for: dayKey, in: context, calendar: calendar)
        guard !sessions.isEmpty else {
            return ["WorkoutSession: none"]
        }
        var lines = ["WorkoutSession (\(sessions.count)):"]
        for session in sessions {
            lines.append("  title=\(session.title) source=\(session.source)")
            let titles = session.exercises.sorted { $0.order < $1.order }.map(\.exerciseTitle)
            if titles.isEmpty {
                lines.append("    exercises: none")
            } else {
                lines.append("    exercises: \(titles.joined(separator: " | "))")
            }
        }
        return lines
    }

    private static func dailyMetric(
        for dayKey: String,
        in context: ModelContext,
        calendar: Calendar
    ) -> DailyMetric? {
        guard let dayStart = startOfDay(forDayKey: dayKey, calendar: calendar),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
        else { return nil }
        let start = dayStart
        let end = dayEnd
        var descriptor = FetchDescriptor<DailyMetric>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func dailyNutrition(
        for dayKey: String,
        in context: ModelContext,
        calendar: Calendar
    ) -> DailyNutrition? {
        guard let dayStart = startOfDay(forDayKey: dayKey, calendar: calendar),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
        else { return nil }
        let start = dayStart
        let end = dayEnd
        var descriptor = FetchDescriptor<DailyNutrition>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func workoutSessions(
        for dayKey: String,
        in context: ModelContext,
        calendar: Calendar
    ) -> [WorkoutSession] {
        guard let dayStart = startOfDay(forDayKey: dayKey, calendar: calendar),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
        else { return [] }
        let start = dayStart
        let end = dayEnd
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func latestNutritionDayKey(
        in context: ModelContext,
        calendar: Calendar
    ) throws -> String? {
        let descriptor = FetchDescriptor<DailyNutrition>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let rows = try context.fetch(descriptor)
        for row in rows where hasLoggedNutrition(row) {
            return Summarizer.dayKey(for: row.date, calendar: calendar)
        }
        return nil
    }

    private static func hasLoggedNutrition(_ row: DailyNutrition) -> Bool {
        row.dietaryEnergyKcal != nil
            || row.proteinG != nil
            || row.carbsG != nil
            || row.fatTotalG != nil
    }

    private static func startOfDay(forDayKey dayKey: String, calendar: Calendar) -> Date? {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func formatOptional(_ value: Double?) -> String {
        guard let value else { return "none" }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
