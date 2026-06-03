import Foundation

struct ISOWeekIdentifier: Sendable, Hashable {
    let yearForWeekOfYear: Int
    let weekOfYear: Int

    var keySegment: String {
        "\(yearForWeekOfYear)-W\(weekOfYear)"
    }

    static func current(calendar: Calendar, referenceDate: Date = Date()) -> ISOWeekIdentifier {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
        return ISOWeekIdentifier(
            yearForWeekOfYear: components.yearForWeekOfYear ?? 0,
            weekOfYear: components.weekOfYear ?? 0
        )
    }

    func dedupeKey(type: InsightType, entity: String) -> String {
        "\(type.rawValue).\(entity).\(keySegment)"
    }

    func volumeExpiry(calendar: Calendar, referenceDate: Date) -> Date? {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate),
              let lastWeekDay = calendar.date(byAdding: .day, value: -1, to: interval.end)
        else {
            return nil
        }
        var endComponents = calendar.dateComponents([.year, .month, .day], from: lastWeekDay)
        endComponents.hour = 23
        endComponents.minute = 59
        endComponents.second = 59
        guard let endOfWeek = calendar.date(from: endComponents) else { return nil }
        return calendar.date(byAdding: .day, value: 2, to: endOfWeek)
    }
}
