import XCTest
@testable import Signal

@MainActor
final class DisplayUnitFormatterTests: XCTestCase {
    private func makePreferences() -> UnitPreferences {
        let suite = "DisplayUnitFormatterTests.\(UUID().uuidString)"
        return UnitPreferences(defaults: UserDefaults(suiteName: suite)!)
    }

    func testFormatMassKilograms() {
        let preferences = makePreferences()
        preferences.massUnit = .kilograms
        let formatter = DisplayUnitFormatter(preferences: preferences)
        XCTAssertEqual(formatter.formatMassKg(80), "80.0 kg")
    }

    func testFormatMassPounds() {
        let preferences = makePreferences()
        preferences.massUnit = .pounds
        let formatter = DisplayUnitFormatter(preferences: preferences)
        let text = formatter.formatMassKg(80)
        XCTAssertTrue(text.hasSuffix("lb"))
        XCTAssertTrue(text.contains("176"))
    }

    func testFormatDistanceMiles() {
        let preferences = makePreferences()
        preferences.distanceUnit = .miles
        let formatter = DisplayUnitFormatter(preferences: preferences)
        let text = formatter.formatDistanceKm(10)
        XCTAssertTrue(text.hasSuffix("mi"))
        XCTAssertTrue(text.contains("6.2"))
    }

    func testDisplayMassConversion() {
        let preferences = makePreferences()
        preferences.massUnit = .pounds
        let formatter = DisplayUnitFormatter(preferences: preferences)
        XCTAssertEqual(formatter.displayMassKg(1), 2.204_622_621_8, accuracy: 0.0001)
    }

    func testParseMassInputRoundTrip() {
        let preferences = makePreferences()
        preferences.massUnit = .pounds
        let formatter = DisplayUnitFormatter(preferences: preferences)
        let kg = formatter.parseMassInputToKg(225)
        XCTAssertEqual(kg, 102.058, accuracy: 0.1)
    }
}
