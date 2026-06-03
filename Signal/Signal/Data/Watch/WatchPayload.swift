import Foundation

struct WatchPayload: Codable, Sendable, Equatable {
    let recoveryScore: Double
    let hrvClassification: String
    let confidence: String
    let todayHRV: Double?
    let todayRestingHR: Double?
    let lastUpdated: Date

    var scoreInt: Int { Int(recoveryScore.rounded()) }

    var scoreColor: String {
        if recoveryScore >= 70 { return "Positive" }
        if recoveryScore >= 40 { return "Warning" }
        return "Negative"
    }

    init(
        recoveryScore: Double,
        hrvClassification: String,
        confidence: String,
        todayHRV: Double?,
        todayRestingHR: Double?,
        lastUpdated: Date
    ) {
        self.recoveryScore = recoveryScore
        self.hrvClassification = hrvClassification
        self.confidence = confidence
        self.todayHRV = todayHRV
        self.todayRestingHR = todayRestingHR
        self.lastUpdated = lastUpdated
    }

    init(score: RecoveryScore, lastUpdated: Date = Date()) {
        recoveryScore = score.value
        hrvClassification = score.hrvClassification.rawValue
        confidence = score.confidence.rawValue
        todayHRV = score.todayHRV
        todayRestingHR = score.todayRestingHR
        self.lastUpdated = lastUpdated
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func encodeToApplicationContext() throws -> [String: Any] {
        let data = try Self.makeEncoder().encode(self)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WatchPayloadCodingError.invalidDictionary
        }
        return dictionary
    }

    static func decode(from applicationContext: [String: Any]) throws -> WatchPayload {
        let data = try JSONSerialization.data(withJSONObject: applicationContext)
        return try makeDecoder().decode(WatchPayload.self, from: data)
    }
}

enum WatchPayloadCodingError: Error {
    case invalidDictionary
}
