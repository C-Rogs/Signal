import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.cameronro.signal"

    static let healthkit = Logger(subsystem: subsystem, category: "healthkit")
    static let `import` = Logger(subsystem: subsystem, category: "import")
    static let vectorstore = Logger(subsystem: subsystem, category: "vectorstore")
    static let embedding = Logger(subsystem: subsystem, category: "embedding")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let recovery = Logger(subsystem: subsystem, category: "recovery")
    static let catalog = Logger(subsystem: subsystem, category: "catalog")
}
