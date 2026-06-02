import Foundation

enum FixturePaths {
    /// `Signal/Signal/SignalTests` → repo root `Development/Signal/`.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var healthExportXML: URL? {
        if let path = ProcessInfo.processInfo.environment["SIGNAL_HEALTH_EXPORT_XML"],
            !path.isEmpty
        {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isReadableFile(atPath: url.path) {
                return url
            }
        }
        let local = repoRoot.appendingPathComponent("fixtures/export.xml")
        return FileManager.default.isReadableFile(atPath: local.path) ? local : nil
    }

    static var hevyCSV: URL? {
        if let path = ProcessInfo.processInfo.environment["SIGNAL_HEVY_CSV"],
            !path.isEmpty
        {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isReadableFile(atPath: url.path) {
                return url
            }
        }
        let candidates = [
            repoRoot.appendingPathComponent("fixtures/HevyExport.csv"),
            repoRoot.appendingPathComponent("fixtures/hevy.csv"),
        ]
        return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    static var hasFullFixtureSet: Bool {
        healthExportXML != nil && hevyCSV != nil
    }
}
