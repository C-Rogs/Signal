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
        let data = try Self.makeEncoder().encode(self)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WatchPayloadCodingError.invalidDictionary
        }
        return dictionary
    }
}

enum WatchPayloadCodingError: Error {
    case invalidDictionary
}
