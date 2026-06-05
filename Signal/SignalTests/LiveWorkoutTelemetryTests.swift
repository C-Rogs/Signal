import Foundation
import Testing
@testable import Signal

struct LiveWorkoutTelemetryTests {
    @Test func packetJSONRoundTrip() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let original = LiveWorkoutTelemetryPacket(
            kind: .heartRateBatch,
            sessionKey: "A1B2C3D4-0000-0000-0000-000000000001",
            timestamp: timestamp,
            heartRateSamples: [
                LiveWorkoutHeartRateSample(bpm: 118, timestamp: timestamp),
                LiveWorkoutHeartRateSample(bpm: 122, timestamp: timestamp.addingTimeInterval(1)),
            ]
        )

        let data = try original.encode()
        let decoded = try LiveWorkoutTelemetryPacket.decode(from: data)

        #expect(decoded == original)
    }

    @Test func sessionControlPacketsEncodeKind() throws {
        let start = LiveWorkoutTelemetryPacket(kind: .sessionStart, sessionKey: "session-1")
        let stop = LiveWorkoutTelemetryPacket(kind: .sessionStop, sessionKey: "session-1")

        let startDecoded = try LiveWorkoutTelemetryPacket.decode(from: try start.encode())
        let stopDecoded = try LiveWorkoutTelemetryPacket.decode(from: try stop.encode())

        #expect(startDecoded.kind == .sessionStart)
        #expect(stopDecoded.kind == .sessionStop)
        #expect(startDecoded.heartRateSamples == nil)
    }

    @Test func throttleAllowsFirstSendAndBlocksEarlyRepeat() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(LiveWorkoutTelemetryThrottle.shouldSend(now: now, lastSent: nil))

        let last = now
        let tooSoon = now.addingTimeInterval(0.5)
        #expect(!LiveWorkoutTelemetryThrottle.shouldSend(now: tooSoon, lastSent: last))

        let ready = now.addingTimeInterval(1.0)
        #expect(LiveWorkoutTelemetryThrottle.shouldSend(now: ready, lastSent: last))
    }

    @Test func coalescedBPMUsesLatestSample() {
        let samples = [
            LiveWorkoutHeartRateSample(bpm: 110, timestamp: Date()),
            LiveWorkoutHeartRateSample(bpm: 128, timestamp: Date()),
        ]
        #expect(LiveWorkoutTelemetryThrottle.coalescedBPM(from: samples) == 128)
        #expect(LiveWorkoutTelemetryThrottle.coalescedBPM(from: []) == nil)
    }

    @Test func trimmedBatchKeepsMostRecentSamples() {
        let samples = (1...8).map { index in
            LiveWorkoutHeartRateSample(bpm: 100 + index, timestamp: Date())
        }
        let trimmed = LiveWorkoutTelemetryThrottle.trimmedBatch(samples, maxCount: 5)
        #expect(trimmed.count == 5)
        #expect(trimmed.map(\.bpm) == [104, 105, 106, 107, 108])
    }

}

@Suite(.serialized)
struct LiveWorkoutOutboundQueueTests {
    @Test func enqueuesSessionControlOnly() {
        _ = LiveWorkoutOutboundQueue.takePending()

        let start = LiveWorkoutTelemetryPacket(kind: .sessionStart, sessionKey: "session-a")
        LiveWorkoutOutboundQueue.enqueue(start)
        #expect(LiveWorkoutOutboundQueue.pending?.kind == .sessionStart)
        #expect(LiveWorkoutOutboundQueue.pending?.sessionKey == "session-a")

        let batch = LiveWorkoutTelemetryPacket(
            kind: .heartRateBatch,
            sessionKey: "session-a",
            heartRateSamples: [LiveWorkoutHeartRateSample(bpm: 120, timestamp: Date())]
        )
        LiveWorkoutOutboundQueue.enqueue(batch)
        #expect(LiveWorkoutOutboundQueue.pending?.kind == .sessionStart)

        _ = LiveWorkoutOutboundQueue.takePending()
        #expect(LiveWorkoutOutboundQueue.pending == nil)
    }

    @Test func lastWinsForSessionStop() {
        _ = LiveWorkoutOutboundQueue.takePending()

        let start = LiveWorkoutTelemetryPacket(kind: .sessionStart, sessionKey: "session-a")
        let stop = LiveWorkoutTelemetryPacket(kind: .sessionStop, sessionKey: "session-a")
        LiveWorkoutOutboundQueue.enqueue(start)
        LiveWorkoutOutboundQueue.enqueue(stop)
        #expect(LiveWorkoutOutboundQueue.pending?.kind == .sessionStop)
        #expect(LiveWorkoutOutboundQueue.pending?.sessionKey == "session-a")

        LiveWorkoutOutboundQueue.clearIfMatching(start)
        #expect(LiveWorkoutOutboundQueue.pending?.kind == .sessionStop)

        LiveWorkoutOutboundQueue.clearIfMatching(stop)
        #expect(LiveWorkoutOutboundQueue.pending == nil)
    }
}
