import Foundation

enum HRVBandClassification: String, Sendable, Equatable {
    case aboveUpperBand
    case withinBand
    case belowLowerBand
    case insufficientData
}

struct HRVAnalysis: Sendable, Equatable {
    let baselineMean: Double
    let baselineSD: Double
    let acuteMean: Double
    let upperBand: Double
    let lowerBand: Double
    let classification: HRVBandClassification
    let dataPointsUsed: Int
}

enum HRVAnalyzer {
    private static let baselinePointCap = 60
    private static let acutePointCap = 7
    private static let minimumPointsForClassification = 14
    private static let bandMultiplier = 0.75

    static func analyze(_ series: [(date: Date, sdnn: Double)]) -> HRVAnalysis {
        let values = series.map(\.sdnn)
        let count = values.count
        let baselineValues = Array(values.suffix(min(baselinePointCap, count)))
        let acuteValues = Array(values.suffix(min(acutePointCap, count)))

        let baselineMean = mean(baselineValues)
        let baselineSD = standardDeviation(baselineValues, mean: baselineMean)
        let acuteMean = mean(acuteValues)
        let upperBand = baselineMean + bandMultiplier * baselineSD
        let lowerBand = baselineMean - bandMultiplier * baselineSD

        let classification = classify(
            dataPointCount: count,
            baselineSD: baselineSD,
            acuteMean: acuteMean,
            upperBand: upperBand,
            lowerBand: lowerBand
        )

        return HRVAnalysis(
            baselineMean: baselineMean,
            baselineSD: baselineSD,
            acuteMean: acuteMean,
            upperBand: upperBand,
            lowerBand: lowerBand,
            classification: classification,
            dataPointsUsed: count
        )
    }

    private static func classify(
        dataPointCount: Int,
        baselineSD: Double,
        acuteMean: Double,
        upperBand: Double,
        lowerBand: Double
    ) -> HRVBandClassification {
        guard dataPointCount >= minimumPointsForClassification, baselineSD > 0 else {
            return .insufficientData
        }
        if acuteMean > upperBand {
            return .aboveUpperBand
        }
        if acuteMean < lowerBand {
            return .belowLowerBand
        }
        return .withinBand
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let sumSquared = values.reduce(0) { partial, value in
            let delta = value - mean
            return partial + delta * delta
        }
        return sqrt(sumSquared / Double(values.count))
    }
}
