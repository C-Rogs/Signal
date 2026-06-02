import Foundation
import os

enum ImportFileAccess {
    /// Never copy Apple Health exports larger than this (streaming only).
    static let maxCopyBytes: Int64 = 32 * 1024 * 1024

    final class Session {
        let url: URL
        private let accessURL: URL
        private let didAccess: Bool
        private var temporaryDirectory: URL?
        private var didRelease = false

        func release() {
            guard !didRelease else { return }
            didRelease = true
            if let temporaryDirectory {
                try? FileManager.default.removeItem(at: temporaryDirectory)
                self.temporaryDirectory = nil
            }
            if didAccess {
                accessURL.stopAccessingSecurityScopedResource()
            }
        }

        fileprivate init(
            url: URL,
            accessURL: URL,
            didAccess: Bool,
            temporaryDirectory: URL? = nil
        ) {
            self.url = url
            self.accessURL = accessURL
            self.didAccess = didAccess
            self.temporaryDirectory = temporaryDirectory
        }
    }

    static func openSession(for pickedURL: URL) throws -> Session {
        let didAccess = pickedURL.startAccessingSecurityScopedResource()
        if !didAccess {
            Log.import.warning(
                "security-scoped access not granted for \(pickedURL.lastPathComponent, privacy: .public)"
            )
        }

        if canOpenInputStream(at: pickedURL) {
            try ensureUbiquitousItemIsDownloaded(at: pickedURL)
            let size = fileSize(of: pickedURL) ?? 0
            Log.import.info(
                "import file will stream in place \(pickedURL.lastPathComponent, privacy: .public) sizeMB=\(Double(size) / 1_048_576, format: .fixed(precision: 1), privacy: .public)"
            )
            return Session(url: pickedURL, accessURL: pickedURL, didAccess: didAccess)
        }

        let size = fileSize(of: pickedURL) ?? .max
        if size > maxCopyBytes {
            throw ImportFileAccessError.fileTooLargeToCopy(
                name: pickedURL.lastPathComponent,
                sizeBytes: size
            )
        }

        Log.import.info(
            "import file copying to temp \(pickedURL.lastPathComponent, privacy: .public) sizeMB=\(Double(size) / 1_048_576, format: .fixed(precision: 1), privacy: .public)"
        )
        let localURL = try copyToTemporaryFile(from: pickedURL)
        let directory = localURL.deletingLastPathComponent()
        return Session(url: localURL, accessURL: pickedURL, didAccess: didAccess, temporaryDirectory: directory)
    }

    private static func canOpenInputStream(at url: URL) -> Bool {
        guard let stream = InputStream(url: url) else { return false }
        stream.open()
        defer { stream.close() }
        return stream.streamStatus == .open
    }

    private static func fileSize(of url: URL) -> Int64? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return Int64(size)
    }

    private static func copyToTemporaryFile(from source: URL) throws -> URL {
        try downloadUbiquitousItemIfNeeded(at: source)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-import", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent(source.lastPathComponent)
        let copyState = CopyState()
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinatorError) { readableURL in
            copyState.copy(from: readableURL, to: destination)
        }
        if let coordinatorError {
            throw ImportFileAccessError.copyFailed(coordinatorError.localizedDescription)
        }
        if let copyError = copyState.error {
            throw ImportFileAccessError.copyFailed(copyError.localizedDescription)
        }
        guard copyState.copied, FileManager.default.isReadableFile(atPath: destination.path) else {
            throw ImportFileAccessError.notReadable(source.lastPathComponent)
        }
        return destination
    }

    private final class CopyState: @unchecked Sendable {
        var copied = false
        var error: Error?

        func copy(from source: URL, to destination: URL) {
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: source, to: destination)
                copied = true
            } catch {
                self.error = error
            }
        }
    }

    private static func downloadUbiquitousItemIfNeeded(at url: URL) throws {
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]),
              values.isUbiquitousItem == true
        else {
            return
        }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    private static func ensureUbiquitousItemIsDownloaded(at url: URL) throws {
        guard let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ]),
            values.isUbiquitousItem == true
        else {
            return
        }

        switch values.ubiquitousItemDownloadingStatus {
        case .current, .downloaded:
            return
        default:
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            throw ImportFileAccessError.cloudItemNotDownloaded(name: url.lastPathComponent)
        }
    }
}

enum ImportFileAccessError: LocalizedError {
    case notReadable(String)
    case copyFailed(String)
    case fileTooLargeToCopy(name: String, sizeBytes: Int64)
    case cloudItemNotDownloaded(name: String)

    var errorDescription: String? {
        switch self {
        case .notReadable(let name):
            return "Could not read \(name). Download it in Files (tap the cloud icon) or move export.xml onto the device, then try again."
        case .copyFailed(let detail):
            return "Could not copy the selected file for import: \(detail)"
        case .cloudItemNotDownloaded(let name):
            return "\(name) is still downloading from iCloud. Open Files, wait until the cloud icon clears, then import again."
        case .fileTooLargeToCopy(let name, let sizeBytes):
            let megabytes = Double(sizeBytes) / 1_048_576
            let sizeLabel = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), megabytes)
            return "\(name) is about \(sizeLabel) MB. Signal streams it in place and cannot duplicate it. Open Files, download export.xml fully (no cloud icon), then import again."
        }
    }
}
