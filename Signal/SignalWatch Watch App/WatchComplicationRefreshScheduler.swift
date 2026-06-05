import Foundation
import os
import WatchKit

@MainActor
enum WatchComplicationRefreshScheduler {
    private static let logger = Logger(
        subsystem: SignalIdentifiers.watchApp,
        category: "watch"
    )

    static func scheduleNextRefreshIfNeeded() {
        let intervalMinutes = WatchComplicationTimelinePolicy.backgroundRefreshMinutes
        let preferred = Date().addingTimeInterval(TimeInterval(intervalMinutes * 60))
        WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: preferred, userInfo: nil) { error in
            if let error {
                logger.error(
                    "complication refresh schedule failed: \(error.localizedDescription, privacy: .public)"
                )
            } else {
                logger.info(
                    "complication refresh scheduled inMin=\(intervalMinutes, privacy: .public)"
                )
            }
        }
    }

    static func performScheduledRefresh() {
        _ = WatchPayloadCache.readPayloadHydratingFromSession()
        WatchComplicationRefresh.reloadTimelineOnly()
        logger.info("complication scheduled refresh completed")
    }
}
