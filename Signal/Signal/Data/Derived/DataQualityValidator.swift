import Foundation

enum DataQualityIssue: String, Sendable {
    case corrected = "corrected"
    case suspectOutlier = "suspectOutlier"
    case statisticalOutlier = "statisticalOutlier"
}

struct DataQualityValidation: Sendable, Equatable {
    let correctedValue: Double?
    let issue: DataQualityIssue?
    let excludeFromAcuteBaseline: Bool

    static let unchanged = DataQualityValidation(
        correctedValue: nil,
        issue: nil,
        excludeFromAcuteBaseline: false
    )
}

enum DataQualityValidator {
    static let spo2MetricKind = "bloodOxygenPct"
    static let restingHRMetricKind = "restingHR"
    static let hrvMetricKind = "hrvSDNN_ms"

    static func validateSpO2(_ value: Double) -> DataQualityValidation {
        guard value > 0, value <= 1.0 else {
            return .unchanged
        }
        return DataQualityValidation(
            correctedValue: value * 100.0,
            issue: .corrected,
            excludeFromAcuteBaseline: false
        )
    }

    static func validateRestingHR(_ value: Double) -> DataQualityValidation {
        guard value < 30 || value > 120 else {
            return .unchanged
        }
        return DataQualityValidation(
            correctedValue: nil,
            issue: .suspectOutlier,
            excludeFromAcuteBaseline: true
        )
    }

    static func validateHRV(sdnn: Double, priorValues: [Double]) -> DataQualityValidation {
        guard priorValues.count >= 2 else { return .unchanged }
        let mean = priorValues.reduce(0, +) / Double(priorValues.count)
        let variance = priorValues.reduce(0.0) { partial, value in
            let delta = value - mean
            return partial + delta * delta
        } / Double(priorValues.count)
        let std = sqrt(variance)
        guard std > 0 else { return .unchanged }
        let z = abs(sdnn - mean) / std
        guard z > 3 else { return .unchanged }
        return DataQualityValidation(
            correctedValue: nil,
            issue: .statisticalOutlier,
            excludeFromAcuteBaseline: true
        )
    }
}
