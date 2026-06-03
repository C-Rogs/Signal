import XCTest
@testable import Signal

final class E1RMCalculatorTests: XCTestCase {
    private let calculator = E1RMCalculator()

    func testEpleyFormula() {
        let result = calculator.epley(weight: 100, reps: 10)
        XCTAssertEqual(result, 100 * (1 + 10.0 / 30.0), accuracy: 0.001)
    }

    func testBrzyckiFormula() {
        let result = calculator.brzycki(weight: 100, reps: 10)
        XCTAssertEqual(result, 100 * 36.0 / 27.0, accuracy: 0.001)
    }

    func testBestAtReps30Boundary() {
        XCTAssertNotNil(calculator.best(weight: 80, reps: 30))
    }

    func testBestNilWhenRepsAbove30() {
        XCTAssertNil(calculator.best(weight: 80, reps: 31))
    }

    func testBestNilWhenWeightZero() {
        XCTAssertNil(calculator.best(weight: 0, reps: 5))
    }

    func testBestNilWhenRepsBelowOne() {
        XCTAssertNil(calculator.best(weight: 80, reps: 0))
    }

    func testBestIsMeanOfEpleyAndBrzycki() {
        let weight = 90.0
        let reps = 8
        let expected = (calculator.epley(weight: weight, reps: reps) + calculator.brzycki(weight: weight, reps: reps)) / 2.0
        let best = calculator.best(weight: weight, reps: reps)
        XCTAssertNotNil(best)
        XCTAssertEqual(best!, expected, accuracy: 0.001)
    }
}
