import Foundation
import SwiftData

@Model
final class DataQualityFlag {
    var date: Date
    var metricKind: String
    var originalValue: Double
    var issue: String
    var wasCorrected: Bool

    init(
        date: Date,
        metricKind: String,
        originalValue: Double,
        issue: String,
        wasCorrected: Bool
    ) {
        self.date = date
        self.metricKind = metricKind
        self.originalValue = originalValue
        self.issue = issue
        self.wasCorrected = wasCorrected
    }
}
