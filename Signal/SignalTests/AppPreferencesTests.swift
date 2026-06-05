import XCTest
@testable import Signal

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testDefaultsEnableAppHaptics() {
        let suiteName = "AppPreferencesTests.defaults"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertTrue(preferences.hapticsEnabled)
    }

    func testHapticsPreferencePersistsOff() {
        let suiteName = "AppPreferencesTests.haptics"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: "signal.app.hapticsEnabled")
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences.hapticsEnabled)
        preferences.hapticsEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "signal.app.hapticsEnabled"))
    }
}
