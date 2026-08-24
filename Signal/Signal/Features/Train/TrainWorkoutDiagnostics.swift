import Foundation
import UIKit

enum TrainWorkoutDiagnostics {
    private static let storageKey = "signal.train.workout.diag"
    private static let maxEntries = 200

    static func beginSession(_ reason: String) {
        record("--- sessionStart reason=\(reason) pid=\(ProcessInfo.processInfo.processIdentifier) ---")
        recordMemory("sessionStart reason=\(reason)")
    }

    static func record(_ message: String) {
        let stamp = Self.timestamp()
        let line = "\(stamp) \(message)"
        NSLog("[SignalTrain] %@", line)
        var entries = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        entries.append(line)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        UserDefaults.standard.set(entries, forKey: storageKey)
    }

    static func recordMemory(_ context: String) {
        record("\(context) \(ProcessMemoryFootprint.diagnosticSuffix())")
    }

    static var hasEntries: Bool {
        !(UserDefaults.standard.stringArray(forKey: storageKey) ?? []).isEmpty
    }

    static func exportText() -> String {
        let entries = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        if entries.isEmpty {
            return "No train workout diagnostics captured yet."
        }
        return entries.joined(separator: "\n")
    }

    static func copyToPasteboardAndReset() -> String {
        let text = exportText()
        UIPasteboard.general.string = text
        clear()
        return text
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
