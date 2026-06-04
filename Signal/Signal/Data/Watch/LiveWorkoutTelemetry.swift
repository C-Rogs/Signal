// Canonical copy; also mirrored in SignalWatch Watch App/LiveWorkoutTelemetry.swift for the watch target.
import Foundation

enum LiveWorkoutTelemetryKind: String, Codable, Sendable {
    case sessionStart
    case sessionStop
    case heartRateBatch
}

struct LiveWorkoutHeartRateSample: Codable, Sendable, Equatable {
    let bpm: Int
    let timestamp: Date
}

enum LiveWorkoutTelemetryUserInfoKey {
    static let payloadData = "signal.liveWorkoutTelemetry"
}

struct LiveWorkoutTelemetryPacket: Codable, Sendable, Equatable {
    let kind: LiveWorkoutTelemetryKind
    let sessionKey: String
    let timestamp: Date
    let heartRateSamples: [LiveWorkoutHeartRateSample]?
    let activityTypeRawValue: UInt?

    init(
        kind: LiveWorkoutTelemetryKind,
        sessionKey: String,
        timestamp: Date = Date(),
        heartRateSamples: [LiveWorkoutHeartRateSample]? = nil,
        activityTypeRawValue: UInt? = nil
    ) {
        self.kind = kind
        self.sessionKey = sessionKey
        self.timestamp = timestamp
        self.heartRateSamples = heartRateSamples
        self.activityTypeRawValue = activityTypeRawValue
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

    func encode() throws -> Data {
        try Self.makeEncoder().encode(self)
    }

    static func decode(from data: Data) throws -> LiveWorkoutTelemetryPacket {
        try makeDecoder().decode(LiveWorkoutTelemetryPacket.self, from: data)
    }
}

enum LiveWorkoutTelemetryThrottle {
    static let defaultMinimumInterval: TimeInterval = 1.0
    static let defaultMaxBatchSize = 5

    static func shouldSend(
        now: Date,
        lastSent: Date?,
        minimumInterval: TimeInterval = defaultMinimumInterval
    ) -> Bool {
        guard let lastSent else { return true }
        return now.timeIntervalSince(lastSent) >= minimumInterval
    }

    static func coalescedBPM(from samples: [LiveWorkoutHeartRateSample]) -> Int? {
        samples.last?.bpm
    }

    static func trimmedBatch(
        _ samples: [LiveWorkoutHeartRateSample],
        maxCount: Int = defaultMaxBatchSize
    ) -> [LiveWorkoutHeartRateSample] {
        guard maxCount > 0 else { return [] }
        if samples.count <= maxCount { return samples }
        return Array(samples.suffix(maxCount))
    }
}
