import Foundation
import SwiftData
import Observation
import os

@MainActor
@Observable
final class ImportViewModel {
    var progress = HealthImportProgress()
    var result: HealthImportResult?
    var errorMessage: String?
    var isImporting = false

    private var importTask: Task<Void, Never>?
    private let modelContainer: ModelContainer
    private let calendar: Calendar

    init(modelContainer: ModelContainer, calendar: Calendar? = nil) {
        self.modelContainer = modelContainer
        if let calendar {
            self.calendar = calendar
        } else {
            var defaultCalendar = Calendar(identifier: .gregorian)
            defaultCalendar.timeZone = .current
            self.calendar = defaultCalendar
        }
    }

    func importExportXML(from url: URL) {
        cancelImport()
        result = nil
        errorMessage = nil
        isImporting = true
        progress = HealthImportProgress(phase: .parsing)

        importTask = Task {
            do {
                let importResult = try await AppleHealthXMLImporter.run(
                    fileURL: url,
                    modelContainer: modelContainer,
                    calendar: calendar
                ) { @Sendable update in
                    Task { @MainActor [weak self] in
                        self?.progress = update
                    }
                }
                self.result = importResult
                if let warning = importResult.sanityWarning {
                    self.errorMessage = warning
                } else if importResult.cancelled {
                    self.errorMessage = "Import cancelled."
                }
                self.isImporting = false
            } catch {
                Log.import.error("import failed: \(String(describing: error), privacy: .public)")
                self.errorMessage = String(describing: error)
                self.progress.phase = .failed
                self.isImporting = false
            }
        }
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        if isImporting {
            progress.phase = .cancelled
        }
        isImporting = false
    }
}
