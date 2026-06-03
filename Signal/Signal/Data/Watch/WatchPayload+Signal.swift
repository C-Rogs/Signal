import Foundation

extension WatchPayload {
    init(score: RecoveryScore, lastUpdated: Date = Date()) {
        self.init(
            recoveryScore: score.value,
            hrvClassification: score.hrvClassification.rawValue,
            confidence: score.confidence.rawValue,
            todayHRV: score.todayHRV,
            todayRestingHR: score.todayRestingHR,
            lastUpdated: lastUpdated
        )
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func encodeToApplicationContext() throws -> [String: Any] {
        var dictionary: [String: Any] = [
            "recoveryScore": recoveryScore,
            "hrvClassification": hrvClassification,
            "confidence": confidence,
            "lastUpdated": Self.iso8601Formatter.string(from: lastUpdated),
        ]
        if let todayHRV {
            dictionary["todayHRV"] = todayHRV
        }
        if let todayRestingHR {
            dictionary["todayRestingHR"] = todayRestingHR
        }
        return dictionary
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
