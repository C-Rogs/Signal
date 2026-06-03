import Foundation

enum InsightFormatting {
    static func relativeDaysAgo(from date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        if days <= 0 {
            return "Today"
        }
        if days == 1 {
            return "1 day ago"
        }
        return "\(days) days ago"
    }
}
