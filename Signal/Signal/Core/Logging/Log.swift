import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? SignalIdentifiers.iosApp

    static let healthkit = Logger(subsystem: subsystem, category: "healthkit")
    static let `import` = Logger(subsystem: subsystem, category: "import")
    static let vectorstore = Logger(subsystem: subsystem, category: "vectorstore")
    static let embedding = Logger(subsystem: subsystem, category: "embedding")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let recovery = Logger(subsystem: subsystem, category: "recovery")
    static let catalog = Logger(subsystem: subsystem, category: "catalog")
    static let workout = Logger(subsystem: subsystem, category: "workout")
    static let backup = Logger(subsystem: subsystem, category: "backup")
    static let coach = Logger(subsystem: subsystem, category: "coach")
    static let heartrate = Logger(subsystem: subsystem, category: "heartrate")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
