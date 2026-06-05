import Foundation

enum TrainWorkoutDiagnostics {
    private static let storageKey = "signal.train.workout.diag"
    private static let maxEntries = 100

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

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
