import Foundation
import SwiftData
import SwiftUI

enum BackupPreferences {
    static let lastExportedAtKey = "signal.backup.lastExportedAt"
}

@MainActor
@Observable
final class SettingsBackupViewModel {
    private let backupService: BackupService

    var isExporting = false
    var isImporting = false
    var exportShareURL: URL?
    var showExportShare = false
    var showImportPicker = false
    var importSuccessMessage: String?
    var showImportSuccess = false
    var errorMessage: String?
    var showError = false

    var lastExportedAt: Date? {
        UserDefaults.standard.object(forKey: BackupPreferences.lastExportedAtKey) as? Date
    }

    var lastExportedLabel: String {
        guard let lastExportedAt else { return "Never" }
        return lastExportedAt.formatted(date: .abbreviated, time: .shortened)
    }

    init(container: ModelContainer) {
        backupService = BackupService(container: container)
    }

    func exportBackup() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }

        do {
            let data = try await backupService.exportJSON()
            let filename = Self.exportFilename(for: .now)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            exportShareURL = url
            UserDefaults.standard.set(Date.now, forKey: BackupPreferences.lastExportedAtKey)
            showExportShare = true
        } catch {
            presentError(error)
        }
    }

    func importBackup(from url: URL) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            let result = try await backupService.importJSON(data)
            importSuccessMessage = Self.importSummary(result)
            showImportSuccess = true
        } catch {
            presentError(error)
        }
    }

    func clearExportShare() {
        exportShareURL = nil
        showExportShare = false
    }

    private func presentError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }

    private static func exportFilename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return "signal-backup-\(formatter.string(from: date)).json"
    }

    private static func importSummary(_ result: BackupImportResult) -> String {
        let sessionLabel = result.importedSessionCount == 1 ? "session" : "sessions"
        let bodyweightLabel = result.importedBodyweightCount == 1 ? "entry" : "entries"
        return "\(result.importedSessionCount) \(sessionLabel), \(result.importedBodyweightCount) bodyweight \(bodyweightLabel) imported."
    }
}
