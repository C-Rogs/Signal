import XCTest
@testable import Signal

final class CoachPreferencesTests: XCTestCase {
    func testDefaultsEnableAllCoachFeatures() {
        let defaults = UserDefaults(suiteName: "CoachPreferencesTests")!
        defaults.removePersistentDomain(forName: "CoachPreferencesTests")
        let flags = CoachFeatureFlags.current(defaults: defaults)
        XCTAssertTrue(flags.smartContextEnabled)
        XCTAssertTrue(flags.deepReasoningEnabled)
        XCTAssertTrue(flags.compoundQueriesEnabled)
    }

    func testLegacyScopeLoadsFullContext() {
        let scope = CoachContextScope.legacy(query: "What should I train today?")
        XCTAssertEqual(scope.ragK, 4)
        XCTAssertTrue(scope.metricsParts.contains(.acwr))
        XCTAssertTrue(scope.metricsParts.contains(.volume))
        XCTAssertTrue(scope.includePersonalReadiness)
    }

    func testSmartContextFlagPersistsOff() {
        let defaults = UserDefaults(suiteName: "CoachPreferencesTests.legacy")!
        defaults.removePersistentDomain(forName: "CoachPreferencesTests.legacy")
        defaults.set(false, forKey: CoachPreferenceKeys.smartContext)
        let flags = CoachFeatureFlags.current(defaults: defaults)
        XCTAssertFalse(flags.smartContextEnabled)
    }
}
