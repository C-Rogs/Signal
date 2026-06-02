import Foundation
import SwiftData
import Observation
import os

@MainActor
@Observable
final class ImportViewModel {
    var healthProgress = HealthImportProgress()
    var healthResult: HealthImportResult?
    var hevyProgress = HevyImportProgress()
    var hevyResult: HevyImportResult?
    var errorMessage: String?
    var isImportingHealth = false
    var isImportingHevy = false

    var isImporting: Bool { isImportingHealth || isImportingHevy }

    private var healthImportTask: Task<Void, Never>?
    private var hevyImportTask: Task<Void, Never>?
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
        cancelHealthImport()
        healthResult = nil
        errorMessage = nil
        isImportingHealth = true
        healthProgress = HealthImportProgress(phase: .parsing)

        healthImportTask = Task {
            var fileSession: ImportFileAccess.Session?
            defer {
                fileSession?.release()
                self.isImportingHealth = false
            }

            do {
                let session = try ImportFileAccess.openSession(for: url)
                fileSession = session
                let fileURL = session.url
                Log.import.info(
                    "health import starting file=\(fileURL.lastPathComponent, privacy: .public)"
                )

                let importResult = try await AppleHealthXMLImporter.run(
                    fileURL: fileURL,
                    modelContainer: modelContainer,
                    calendar: calendar,
                    onParseFinished: {
                        fileSession?.release()
                        fileSession = nil
                        Log.import.info("health import released export file before embedding")
                    }
                ) { @Sendable update in
                    Task { @MainActor [weak self] in
                        self?.healthProgress = update
                    }
                }

                self.healthResult = importResult
                ImportSummaryStore.recordHealth(importResult)
                self.errorMessage = Self.healthImportMessage(
                    for: importResult,
                    progress: self.healthProgress
                )
                if self.errorMessage != nil {
                    self.healthProgress.phase = .failed
                }

                Log.import.info(
                    "health import finished scanned=\(importResult.recordsScanned, privacy: .public) metrics=\(importResult.dailyMetricCount, privacy: .public) vectors=\(importResult.healthVectorCount, privacy: .public) warning=\(importResult.sanityWarning ?? "none", privacy: .public)"
                )
            } catch {
                Log.import.error("health import failed: \(String(describing: error), privacy: .public)")
                self.errorMessage = Self.describeImportFailure(error, kind: "Health")
                self.healthProgress.phase = .failed
            }
        }
    }

    func importHevyCSV(from url: URL) {
        cancelHevyImport()
        hevyResult = nil
        errorMessage = nil
        isImportingHevy = true
        hevyProgress = HevyImportProgress(phase: .parsing)

        hevyImportTask = Task {
            var fileSession: ImportFileAccess.Session?
            defer {
                fileSession?.release()
                self.isImportingHevy = false
            }

            do {
                let session = try ImportFileAccess.openSession(for: url)
                fileSession = session
                let fileURL = session.url
                Log.import.info(
                    "Hevy import starting file=\(fileURL.lastPathComponent, privacy: .public)"
                )

                let importResult = try await HevyCSVImporter.run(
                    fileURL: fileURL,
                    modelContainer: modelContainer,
                    calendar: calendar
                ) { @Sendable update in
                    Task { @MainActor [weak self] in
                        self?.hevyProgress = update
                    }
                }
                self.hevyResult = importResult
                ImportSummaryStore.recordHevy(importResult)
                if importResult.cancelled {
                    self.errorMessage = "Hevy import cancelled."
                    self.hevyProgress.phase = .failed
                } else {
                    self.errorMessage = nil
                }
            } catch let error as HevyCSVParseError {
                Log.import.error("Hevy import failed: \(String(describing: error), privacy: .public)")
                switch error {
                case .unexpectedHeaders(let found, _):
                    self.errorMessage = "Unexpected CSV headers: \(found)"
                default:
                    self.errorMessage = error.localizedDescription
                }
                self.hevyProgress.phase = .failed
            } catch {
                Log.import.error("Hevy import failed: \(String(describing: error), privacy: .public)")
                self.errorMessage = Self.describeImportFailure(error, kind: "Hevy")
                self.hevyProgress.phase = .failed
            }
        }
    }

    func resetStuckImportFlagsIfIdle() {
        if healthImportTask == nil {
            isImportingHealth = false
        }
        if hevyImportTask == nil {
            isImportingHevy = false
        }
    }

    func cancelHealthImport() {
        healthImportTask?.cancel()
        healthImportTask = nil
        if isImportingHealth {
            healthProgress.phase = .cancelled
        }
        isImportingHealth = false
    }

    func cancelHevyImport() {
        hevyImportTask?.cancel()
        hevyImportTask = nil
        if isImportingHevy {
            hevyProgress.phase = .cancelled
        }
        isImportingHevy = false
    }

    private static func healthImportMessage(
        for result: HealthImportResult,
        progress: HealthImportProgress
    ) -> String? {
        if let warning = result.sanityWarning {
            return "Health import rejected: \(warning)"
        }
        if result.cancelled {
            return "Health import cancelled."
        }
        if result.recordsScanned == 0 {
            return "Could not read export.xml. Unzip export.zip in Files, select export.xml (not the zip), and ensure the file is downloaded locally."
        }
        if progress.dailyMetricsWritten == 0, result.recordsScanned > 0 {
            return "Health parse finished but no DailyMetric rows were stored."
        }
        if progress.vectorsWritten == 0, progress.dailyMetricsWritten > 0 {
            return "Health metrics saved but embedding produced 0 vectors. Check that MLX EmbeddingGemma weights are present on this device."
        }
        return nil
    }

    private static func describeImportFailure(_ error: Error, kind: String) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return "\(kind) import failed: \(description)"
        }
        return "\(kind) import failed: \(error.localizedDescription)"
    }
}
