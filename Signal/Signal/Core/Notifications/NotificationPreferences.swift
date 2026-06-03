import Foundation
import Observation

@MainActor
@Observable
final class NotificationPreferences {
    static let shared = NotificationPreferences()

    var dailyBriefingEnabled: Bool {
        didSet { persistEnabled() }
    }

    var briefingHour: Int {
        didSet { persistHour() }
    }

    var briefingMinute: Int {
        didSet { persistMinute() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.enabledKey) != nil {
            dailyBriefingEnabled = defaults.bool(forKey: Self.enabledKey)
        } else {
            dailyBriefingEnabled = true
        }
        let hour = defaults.integer(forKey: Self.hourKey)
        briefingHour = (8...22).contains(hour) ? hour : Self.defaultHour
        let minute = defaults.integer(forKey: Self.minuteKey)
        briefingMinute = (0...59).contains(minute) ? minute : Self.defaultMinute
    }

    var briefingDateComponents: DateComponents {
        DateComponents(hour: briefingHour, minute: briefingMinute)
    }

    private func persistEnabled() {
        defaults.set(dailyBriefingEnabled, forKey: Self.enabledKey)
    }

    private func persistHour() {
        defaults.set(briefingHour, forKey: Self.hourKey)
    }

    private func persistMinute() {
        defaults.set(briefingMinute, forKey: Self.minuteKey)
    }

    private static let enabledKey = "signal.notifications.dailyBriefingEnabled"
    private static let hourKey = "signal.notifications.briefingHour"
    private static let minuteKey = "signal.notifications.briefingMinute"
    static let defaultHour = 7
    static let defaultMinute = 0
}
