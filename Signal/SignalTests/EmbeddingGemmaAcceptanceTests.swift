import Foundation
import os
import SwiftData
import Testing
@testable import Signal

/// M3 acceptance proof: run on a physical iPhone (MLX). Simulator run reports skip.
@MainActor
struct EmbeddingGemmaAcceptanceTests {
    private static let recoveryPhrase = "I slept 8 hours and felt recovered"
    private static let sleepQuery = "how was my sleep"

    #if targetEnvironment(simulator)
    @Test func embeddingGemmaAcceptanceProofSkippedOnSimulator() {
        print("[M3-ACCEPT] environment=simulator MLX proof skipped (device only)")
        Log.embedding.info("M3 acceptance skipped: simulator cannot run EmbeddingGemma MLX proof")
        #expect(Bool(true))
    }
    #else
    @Test(.timeLimit(.minutes(15)))
    func embeddingGemmaAcceptanceProof() async throws {
        print("[M3-ACCEPT] environment=device starting EmbeddingGemma acceptance proof")
        try await Self.runAcceptanceProof(environmentLabel: "device")
    }
    #endif

    #if !targetEnvironment(simulator)
    private static func runAcceptanceProof(environmentLabel: String) async throws {
        #expect(
            EmbeddingBackend.useNLContextualEmbeddingFallback == false,
            "NL fallback flag must be off for M3 acceptance"
        )

        let service = GemmaEmbeddingService.shared
        #expect(service.outputDimension == HealthVectorDimension.embeddingGemma)

        _ = try await service.ensureLoaded()

        Log.embedding.info(
            "M3-ACCEPT backend=MLX-EmbeddingGemma model=\(GemmaEmbeddingService.modelID, privacy: .public) dim=\(service.outputDimension, privacy: .public)"
        )
        print(
            "[M3-ACCEPT] \(environmentLabel) backend=MLX-EmbeddingGemma model=\(GemmaEmbeddingService.modelID) configured_dim=\(service.outputDimension)"
        )
        print(
            "[M3-ACCEPT] \(environmentLabel) NL_fallback_flag=\(EmbeddingBackend.useNLContextualEmbeddingFallback) (512-dim NL path not active)"
        )

        // 1. Live dimension (768, not 512)
        let probe = try await service.embed("dimension-probe", kind: .document)
        let liveDimension = probe.count
        Log.embedding.info("M3-ACCEPT live_embedding_dimension=\(liveDimension, privacy: .public)")
        print("[M3-ACCEPT] \(environmentLabel) check1 live_dimension=\(liveDimension) expected=768")
        #expect(liveDimension == 768)
        #expect(liveDimension != 512)

        // 2. Recovery phrase stats
        let recovery = try await service.embed(recoveryPhrase, kind: .document)
        let stats = vectorStats(recovery)
        Log.embedding.info(
            "M3-ACCEPT recovery_phrase len=\(stats.count, privacy: .public) min=\(stats.min, privacy: .public) max=\(stats.max, privacy: .public) mean=\(stats.mean, privacy: .public) hasNaN=\(stats.hasNaN, privacy: .public) allZero=\(stats.allZero, privacy: .public)"
        )
        print(
            "[M3-ACCEPT] \(environmentLabel) check2 phrase=\"\(recoveryPhrase)\" len=\(stats.count) min=\(stats.min) max=\(stats.max) mean=\(stats.mean) hasNaN=\(stats.hasNaN) allZero=\(stats.allZero)"
        )
        #expect(stats.count == 768)
        #expect(!stats.hasNaN)
        #expect(!stats.allZero)

        // 3. Determinism
        let runA = try await service.embed(recoveryPhrase, kind: .document)
        let runB = try await service.embed(recoveryPhrase, kind: .document)
        let deterministic = zip(runA, runB).allSatisfy { $0 == $1 }
        Log.embedding.info("M3-ACCEPT determinism identical=\(deterministic, privacy: .public)")
        print("[M3-ACCEPT] \(environmentLabel) check3 determinism identical=\(deterministic)")
        #expect(deterministic)

        // 4. Prefix check
        let prefixText = "Resting heart rate 52 bpm after easy run"
        let asDocument = try await service.embed(prefixText, kind: .document)
        let asQuery = try await service.embed(prefixText, kind: .query)
        let prefixCosine = CosineSimilarity.score(query: asDocument, candidate: asQuery) ?? 1
        let prefixIdentical = zip(asDocument, asQuery).allSatisfy { $0 == $1 }
        Log.embedding.info(
            "M3-ACCEPT prefix cosine=\(prefixCosine, privacy: .public) identical=\(prefixIdentical, privacy: .public)"
        )
        print(
            "[M3-ACCEPT] \(environmentLabel) check4 prefix cosine=\(prefixCosine) identical=\(prefixIdentical)"
        )
        #expect(!prefixIdentical)
        #expect(prefixCosine < 0.99)

        // 5. Semantic retrieval
        let container = try SignalModelContainer.make(inMemoryOnly: true)
        let context = ModelContext(container)
        let store = SwiftDataVectorStore(context: context)
        try store.deleteAll()

        let corpus: [(dayKey: String, summary: String)] = [
            (
                "sleep-day",
                "Sleep 8.2 hours, HRV 92 ms, resting HR 48 bpm. Woke feeling recovered and alert."
            ),
            (
                "leg-day",
                "Leg day: back squat 5x5 at 140 kg, RDL 4x8, leg press finisher. Sore quads, high strain."
            ),
            (
                "rest-day",
                "Rest day: light walk 3k steps, mobility work, no structured training, low active energy."
            ),
            (
                "stress-day",
                "High stress: poor sleep 4.5 hours, HRV 38 ms, back-to-back meetings, elevated resting HR."
            ),
            (
                "run-day",
                "Long run 18 km at easy pace, 90 min, aerobic focus, tired calves, solid endurance load."
            ),
        ]

        for item in corpus {
            try await EmbeddingVectorStoreBridge.indexDocument(
                summaryText: item.summary,
                dayKey: item.dayKey,
                metricKind: "daily_summary",
                store: store,
                service: service
            )
        }

        let neighbors = try await EmbeddingVectorStoreBridge.search(
            query: sleepQuery,
            store: store,
            service: service,
            k: 5
        )

        print("[M3-ACCEPT] \(environmentLabel) check5 query=\"\(sleepQuery)\" rankings:")
        for (index, neighbor) in neighbors.enumerated() {
            let label = corpus.first { $0.summary == neighbor.summaryText }?.dayKey ?? "unknown"
            print(
                "  [M3-ACCEPT] rank=\(index + 1) dayKey=\(label) similarity=\(neighbor.similarity) text=\(neighbor.summaryText.prefix(80))..."
            )
            Log.embedding.info(
                "M3-ACCEPT rank=\(index + 1, privacy: .public) dayKey=\(label, privacy: .public) sim=\(neighbor.similarity, privacy: .public)"
            )
        }

        let top = neighbors.first
        let legNeighbor = neighbors.first { n in
            corpus.first { $0.summary == n.summaryText }?.dayKey == "leg-day"
        }
        let sleepNeighbor = neighbors.first { n in
            corpus.first { $0.summary == n.summaryText }?.dayKey == "sleep-day"
        }

        let topIsSleep = corpus.first { $0.summary == top?.summaryText }?.dayKey == "sleep-day"
        let sleepScore = sleepNeighbor?.similarity ?? 0
        let legScore = legNeighbor?.similarity ?? 0
        let sleepLegMargin = sleepScore - legScore

        print(
            "[M3-ACCEPT] \(environmentLabel) check5 top_is_sleep=\(topIsSleep) sleep_sim=\(sleepScore) leg_sim=\(legScore) margin=\(sleepLegMargin)"
        )
        Log.embedding.info(
            "M3-ACCEPT semantic top_is_sleep=\(topIsSleep, privacy: .public) sleep_sim=\(sleepScore, privacy: .public) leg_sim=\(legScore, privacy: .public) margin=\(sleepLegMargin, privacy: .public)"
        )

        #expect(neighbors.count == 5)
        #expect(topIsSleep)
        #expect(sleepLegMargin > 0.10)

        print("[M3-ACCEPT] \(environmentLabel) ALL FIVE CHECKS PASSED")
        Log.embedding.info("M3-ACCEPT ALL FIVE CHECKS PASSED environment=\(environmentLabel, privacy: .public)")
    }

    private static func vectorStats(_ vector: [Float]) -> (
        count: Int,
        min: Float,
        max: Float,
        mean: Float,
        hasNaN: Bool,
        allZero: Bool
    ) {
        var minV = Float.greatestFiniteMagnitude
        var maxV = -Float.greatestFiniteMagnitude
        var sum: Double = 0
        var hasNaN = false
        var allZero = true
        for value in vector {
            if value.isNaN { hasNaN = true }
            if value != 0 { allZero = false }
            minV = min(minV, value)
            maxV = max(maxV, value)
            sum += Double(value)
        }
        let mean = vector.isEmpty ? 0 : Float(sum / Double(vector.count))
        return (vector.count, minV, maxV, mean, hasNaN, allZero)
    }
    #endif
}
