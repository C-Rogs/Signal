import XCTest
@testable import Signal

final class TrainNumpadLogicTests: XCTestCase {
    func testAppendDigit() {
        XCTAssertEqual(TrainNumpadLogic.appendDigit("5", to: "12", allowsDecimal: false), "125")
        XCTAssertEqual(TrainNumpadLogic.appendDigit("0", to: "", allowsDecimal: false), "0")
        XCTAssertNil(TrainNumpadLogic.appendDigit("a", to: "", allowsDecimal: false))
    }

    func testAppendDigitRespectsMaxLength() {
        XCTAssertEqual(TrainNumpadLogic.appendDigit("9", to: "123", allowsDecimal: false, maxLength: 3), nil)
        XCTAssertEqual(TrainNumpadLogic.appendDigit("4", to: "12", allowsDecimal: false, maxLength: 3), "124")
    }

    func testAppendDecimal() {
        XCTAssertEqual(TrainNumpadLogic.appendDecimal(to: "12"), "12.")
        XCTAssertEqual(TrainNumpadLogic.appendDecimal(to: ""), "0.")
        XCTAssertNil(TrainNumpadLogic.appendDecimal(to: "12.5"))
    }

    func testBackspace() {
        XCTAssertEqual(TrainNumpadLogic.backspace("125"), "12")
        XCTAssertEqual(TrainNumpadLogic.backspace(""), "")
    }

    func testClear() {
        XCTAssertEqual(TrainNumpadLogic.clear(), "")
    }
}
