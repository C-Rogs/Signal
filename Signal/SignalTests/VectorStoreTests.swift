import Accelerate
import Foundation
import SwiftData
import Testing
@testable import Signal

@MainActor
struct VectorStoreTests {
    private static let dimensions = HealthVectorDimension.embeddingGemma

    @Test func nearestNeighborsRanksTargetFirst() throws {
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let store = SwiftDataVectorStore(context: context)

        let target = Self.unitVector(dimensions: Self.dimensions, axis: 0)
        try store.insert(
            dayKey: "2026-01-01",
            metricKind: "daily_summary",
            summaryText: "target-summary",
            vector: target
        )

        for index in 0 ..< 50 {
            let vector = Self.randomUnitVector(
                dimensions: Self.dimensions,
                seed: UInt64(index + 1)
            )
            try store.insert(
                dayKey: "noise-\(index)",
                metricKind: "noise",
                summaryText: "noise-\(index)",
                vector: vector
            )
        }

        #expect(try store.count() == 51)

        let neighbors = try store.nearestNeighbors(query: target, k: 5)
        #expect(neighbors.first?.summaryText == "target-summary")
        #expect(neighbors.first?.similarity ?? 0 > 0.99)

        try store.deleteAll()
        #expect(try store.count() == 0)
    }

    private static func unitVector(dimensions: Int, axis: Int) -> [Float] {
        var values = [Float](repeating: 0, count: dimensions)
        guard dimensions > 0, axis >= 0, axis < dimensions else { return values }
        values[axis] = 1
        return values
    }

    private static func randomUnitVector(dimensions: Int, seed: UInt64) -> [Float] {
        var generator = SeededGenerator(seed: seed)
        var values = (0 ..< dimensions).map { _ in
            Float.random(in: -1 ... 1, using: &generator)
        }
        var normSquared: Float = 0
        values.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            vDSP_svesq(base, 1, &normSquared, vDSP_Length(dimensions))
        }
        let norm = sqrtf(normSquared)
        guard norm > 0 else { return Self.unitVector(dimensions: dimensions, axis: 1) }
        return values.map { $0 / norm }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }
}
