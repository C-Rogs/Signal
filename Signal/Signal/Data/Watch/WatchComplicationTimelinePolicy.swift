import Foundation

enum WatchComplicationTimelinePolicy {
    /// How often the widget extension re-reads cached payload when data is present.
    static let activeRefreshMinutes = 15

    /// How often to retry when no payload is cached yet.
    static let waitingRefreshMinutes = 5

    /// watchOS background refresh interval (matches active refresh).
    static let backgroundRefreshMinutes = activeRefreshMinutes

    static func nextReloadDate(
        after date: Date,
        isWaiting: Bool,
        calendar: Calendar = .current
    ) -> Date {
        if isWaiting {
            return calendar.date(
                byAdding: .minute,
                value: waitingRefreshMinutes,
                to: date
            ) ?? date.addingTimeInterval(TimeInterval(waitingRefreshMinutes * 60))
        }
        return calendar.date(
            byAdding: .minute,
            value: activeRefreshMinutes,
            to: date
        ) ?? date.addingTimeInterval(TimeInterval(activeRefreshMinutes * 60))
    }
}
