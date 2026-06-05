import Foundation
import os
import WidgetKit

enum RecoveryComplicationKind {
    static let widgetKind = "RecoveryComplication"
}

enum BodyBatteryComplicationKind {
    static let widgetKind = "BodyBatteryComplication"
}

enum RecoveryBatteryInlineComplicationKind {
    static let widgetKind = "RecoveryBatteryInlineComplication"
}

enum WatchComplicationRefresh {
    private static let logger = Logger(
        subsystem: SignalIdentifiers.watchApp,
        category: "watch"
    )

    static func publish(context: [String: Any]) {
        let cached = WatchPayloadCache.write(context: context)
        reloadAllComplicationKinds()
        logger.info(
            "watch complication reload all kinds cache=\(cached, privacy: .public)"
        )
    }

    static func reloadTimelineOnly() {
        reloadAllComplicationKinds()
        logger.info("watch complication timeline reload only all kinds")
    }

    private static func reloadAllComplicationKinds() {
        WidgetCenter.shared.reloadTimelines(ofKind: RecoveryComplicationKind.widgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: BodyBatteryComplicationKind.widgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: RecoveryBatteryInlineComplicationKind.widgetKind)
    }
}
