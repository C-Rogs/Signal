import XCTest
@testable import Signal

final class DataQualityValidatorTests: XCTestCase {
    func testSpO2FractionalDetectionCorrectedToPercent() {
        let validation = DataQualityValidator.validateSpO2(0.95)
        XCTAssertEqual(validation.correctedValue!, 95.0, accuracy: 0.001)
        XCTAssertEqual(validation.issue, .corrected)
    }

    func testRestingHRSuspectOutlierLow() {
        let validation = DataQualityValidator.validateRestingHR(25)
        XCTAssertEqual(validation.issue, .suspectOutlier)
        XCTAssertTrue(validation.excludeFromAcuteBaseline)
    }

    func testRestingHRSuspectOutlierHigh() {
        let validation = DataQualityValidator.validateRestingHR(130)
        XCTAssertEqual(validation.issue, .suspectOutlier)
    }

    func testRestingHRNormalUnchanged() {
        let validation = DataQualityValidator.validateRestingHR(58)
        XCTAssertNil(validation.issue)
    }

    func testHRVStatisticalOutlierBeyondThreeSD() {
        let history: [Double] = [48, 50, 52, 49, 51, 50, 50, 49, 51, 50, 48, 52, 49, 51, 50, 50, 49, 51, 50, 49]
        let validation = DataQualityValidator.validateHRV(sdnn: 100, priorValues: history)
        XCTAssertEqual(validation.issue, .statisticalOutlier)
        XCTAssertTrue(validation.excludeFromAcuteBaseline)
    }

    func testHRVWithinThreeSDUnchanged() {
        let history: [Double] = [48, 50, 52, 49, 51, 50, 50, 49, 51, 50]
        let validation = DataQualityValidator.validateHRV(sdnn: 52, priorValues: history)
        XCTAssertNil(validation.issue)
    }
}
