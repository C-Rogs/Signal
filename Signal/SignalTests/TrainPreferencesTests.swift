import XCTest
@testable import Signal

@MainActor
final class TrainPreferencesTests: XCTestCase {
    func testDefaultsEnableTrainFeedback() {
        let suiteName = "TrainPreferencesTests.defaults"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = TrainPreferences(defaults: defaults)
        XCTAssertTrue(preferences.hapticsEnabled)
        XCTAssertTrue(preferences.restBellEnabled)
    }

    func testHapticsPreferencePersistsOff() {
        let suiteName = "TrainPreferencesTests.haptics"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: "signal.train.hapticsEnabled")
        let preferences = TrainPreferences(defaults: defaults)
        XCTAssertFalse(preferences.hapticsEnabled)
        preferences.hapticsEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "signal.train.hapticsEnabled"))
    }

    func testRestBellPreferencePersistsOff() {
        let suiteName = "TrainPreferencesTests.bell"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: "signal.train.restBellEnabled")
        let preferences = TrainPreferences(defaults: defaults)
        XCTAssertFalse(preferences.restBellEnabled)
        preferences.restBellEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "signal.train.restBellEnabled"))
    }
}
