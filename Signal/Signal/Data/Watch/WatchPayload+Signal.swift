import Foundation

extension WatchPayload {
    init(score: RecoveryScore, personalReadiness: PersonalReadinessProfile? = nil, lastUpdated: Date = Date()) {
        self.init(
            recoveryScore: score.value,
            hrvClassification: score.hrvClassification.rawValue,
            confidence: score.confidence.rawValue,
            todayHRV: score.todayHRV,
            todayRestingHR: score.todayRestingHR,
            lastUpdated: lastUpdated,
            personalP25: personalReadiness?.isCalibrated == true ? personalReadiness?.personalP25 : nil,
            personalP75: personalReadiness?.isCalibrated == true ? personalReadiness?.personalP75 : nil,
            isCalibrated: personalReadiness?.isCalibrated
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
        if let personalP25 {
            dictionary["personalP25"] = personalP25
        }
        if let personalP75 {
            dictionary["personalP75"] = personalP75
        }
        if let isCalibrated {
            dictionary["isCalibrated"] = isCalibrated
        }
        return dictionary
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
