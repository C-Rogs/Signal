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

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func decode(from applicationContext: [String: Any]) throws -> WatchPayload {
        let data = try JSONSerialization.data(withJSONObject: applicationContext)
        return try makeDecoder().decode(WatchPayload.self, from: data)
    }
}
