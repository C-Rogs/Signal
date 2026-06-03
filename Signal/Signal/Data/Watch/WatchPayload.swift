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

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func decode(from applicationContext: [String: Any]) throws -> WatchPayload {
        guard !applicationContext.isEmpty else {
            throw WatchPayloadCodingError.emptyContext
        }

        guard let recoveryScore = doubleValue(in: applicationContext, key: "recoveryScore"),
              let hrvClassification = applicationContext["hrvClassification"] as? String,
              let confidence = applicationContext["confidence"] as? String,
              let lastUpdated = dateValue(in: applicationContext, key: "lastUpdated")
        else {
            throw WatchPayloadCodingError.invalidDictionary
        }

        return WatchPayload(
            recoveryScore: recoveryScore,
            hrvClassification: hrvClassification,
            confidence: confidence,
            todayHRV: doubleValue(in: applicationContext, key: "todayHRV"),
            todayRestingHR: doubleValue(in: applicationContext, key: "todayRestingHR"),
            lastUpdated: lastUpdated
        )
    }

    private static func doubleValue(in dictionary: [String: Any], key: String) -> Double? {
        if let value = dictionary[key] as? Double { return value }
        if let value = dictionary[key] as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func dateValue(in dictionary: [String: Any], key: String) -> Date? {
        if let value = dictionary[key] as? Date { return value }
        if let value = dictionary[key] as? String {
            return iso8601Formatter.date(from: value)
        }
        return nil
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum WatchPayloadCodingError: Error {
    case invalidDictionary
    case emptyContext
}
