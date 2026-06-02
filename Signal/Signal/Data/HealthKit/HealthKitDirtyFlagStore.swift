import Foundation

enum HealthKitDirtyFlagStore {
    private static let key = "com.cameronro.signal.healthKitSyncDirty"

    static var isDirty: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func setDirty() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.set(false, forKey: key)
    }
}
