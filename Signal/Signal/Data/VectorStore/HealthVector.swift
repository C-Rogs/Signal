import Foundation
import SwiftData

enum HealthVectorDimension {
    static let embeddingGemma = 768
}

@Model
final class HealthVector {
    var dayKey: String
    var metricKind: String
    var summaryText: String
    var vector: [Float]

    init(
        dayKey: String,
        metricKind: String,
        summaryText: String,
        vector: [Float]
    ) {
        self.dayKey = dayKey
        self.metricKind = metricKind
        self.summaryText = summaryText
        self.vector = vector
    }
}
