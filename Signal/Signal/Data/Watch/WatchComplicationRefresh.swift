import Foundation
import os
import WidgetKit

enum RecoveryComplicationKind {
    static let widgetKind = "RecoveryComplication"
}

enum WatchComplicationRefresh {
    private static let logger = Logger(
        subsystem: SignalIdentifiers.watchApp,
        category: "watch"
    )

    static func publish(context: [String: Any]) {
        let cached = WatchPayloadCache.write(context: context)
        WidgetCenter.shared.reloadTimelines(ofKind: RecoveryComplicationKind.widgetKind)
        logger.info(
            "watch complication reload kind=\(RecoveryComplicationKind.widgetKind, privacy: .public) cache=\(cached, privacy: .public)"
        )
    }

    static func reloadTimelineOnly() {
        WidgetCenter.shared.reloadTimelines(ofKind: RecoveryComplicationKind.widgetKind)
        logger.info("watch complication timeline reload only")
    }
}
