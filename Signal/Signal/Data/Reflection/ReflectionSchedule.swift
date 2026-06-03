import Foundation

enum ReflectionSchedule {
    private static let lastReflectionKey = "signal.lastReflectionDate"
    private static let foregroundInterval: TimeInterval = 6 * 3600

    static func shouldRunOnForeground(now: Date = Date()) -> Bool {
        guard let last = UserDefaults.standard.object(forKey: lastReflectionKey) as? Date else {
            return true
        }
        return now.timeIntervalSince(last) > foregroundInterval
    }

    static func markReflectionCompleted(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: lastReflectionKey)
    }
}
