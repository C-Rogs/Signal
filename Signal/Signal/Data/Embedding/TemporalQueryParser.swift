import Foundation

struct TemporalQueryWindow: Sendable, Equatable {
    let fromDayKey: String
    let toDayKey: String
    let label: String

    func contains(dayKey: String) -> Bool {
        dayKey >= fromDayKey && dayKey <= toDayKey
    }
}

enum TemporalQueryParser {
    static func window(
        in query: String,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TemporalQueryWindow? {
        let normalized = query
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")

        if normalized.contains("yesterday") {
            let day = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
            let key = Summarizer.dayKey(for: day, calendar: calendar)
            return TemporalQueryWindow(fromDayKey: key, toDayKey: key, label: "yesterday")
        }

        if normalized.contains("last week") || normalized.contains("past week") {
            return rollingDayWindow(
                daysInclusive: 7,
                referenceDate: referenceDate,
                calendar: calendar,
                label: "last 7 days"
            )
        }

        if let rollingDays = rollingDayCount(in: normalized) {
            return rollingDayWindow(
                daysInclusive: rollingDays,
                referenceDate: referenceDate,
                calendar: calendar,
                label: "last \(rollingDays) days"
            )
        }

        if normalized.contains("this week") {
            let end = calendar.startOfDay(for: referenceDate)
            let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate)
            let start = interval?.start ?? end
            return TemporalQueryWindow(
                fromDayKey: Summarizer.dayKey(for: start, calendar: calendar),
                toDayKey: Summarizer.dayKey(for: end, calendar: calendar),
                label: "this week"
            )
        }

        if normalized.contains("last month") || normalized.contains("past month") {
            return rollingDayWindow(
                daysInclusive: 30,
                referenceDate: referenceDate,
                calendar: calendar,
                label: "last 30 days"
            )
        }

        return nil
    }

    static func hasRecencyIntent(
        in query: String,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        if window(in: query, referenceDate: referenceDate, calendar: calendar) != nil {
            return false
        }

        let normalized = query
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")

        if rollingDayCount(in: normalized) != nil { return false }

        if normalized.contains("when was my last") { return true }
        if normalized.contains("when did i last") { return true }
        if normalized.contains("most recent") { return true }
        if normalized.contains("latest") { return true }
        if normalized.contains("previous") { return true }
        if normalized.contains(" my last ") { return true }

        return normalized.range(
            of: #"(?<![a-z])last(?![a-z])"#,
            options: .regularExpression
        ) != nil
    }

    private static func rollingDayCount(in normalized: String) -> Int? {
        let pattern = #"(?:last|past|previous)\s+(\d{1,3})\s+days?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(normalized.startIndex ..< normalized.endIndex, in: normalized)
        guard let match = regex.firstMatch(in: normalized, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: normalized)
        else { return nil }

        let value = Int(normalized[captureRange]) ?? 0
        guard value >= 1, value <= 366 else { return nil }
        return value
    }

    static func dayKeyOnOrAfter(
        daysBack: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let end = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .day, value: -max(0, daysBack), to: end) ?? end
        return Summarizer.dayKey(for: start, calendar: calendar)
    }

    private static func rollingDayWindow(
        daysInclusive: Int,
        referenceDate: Date,
        calendar: Calendar,
        label: String
    ) -> TemporalQueryWindow {
        let end = calendar.startOfDay(for: referenceDate)
        let offset = max(0, daysInclusive - 1)
        let start = calendar.date(byAdding: .day, value: -offset, to: end) ?? end
        return TemporalQueryWindow(
            fromDayKey: Summarizer.dayKey(for: start, calendar: calendar),
            toDayKey: Summarizer.dayKey(for: end, calendar: calendar),
            label: label
        )
    }
}
