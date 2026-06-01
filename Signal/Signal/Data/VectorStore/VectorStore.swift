import Accelerate
import Foundation
import SwiftData

struct VectorNeighbor: Sendable, Equatable {
    let summaryText: String
    let similarity: Float
}

@MainActor
protocol VectorStore: AnyObject {
    func insert(
        dayKey: String,
        metricKind: String,
        summaryText: String,
        vector: [Float]
    ) throws

    func nearestNeighbors(query: [Float], k: Int) throws -> [VectorNeighbor]

    func count() throws -> Int

    func deleteAll() throws
}

@MainActor
final class SwiftDataVectorStore: VectorStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func insert(
        dayKey: String,
        metricKind: String,
        summaryText: String,
        vector: [Float]
    ) throws {
        do {
            let row = HealthVector(
                dayKey: dayKey,
                metricKind: metricKind,
                summaryText: summaryText,
                vector: vector
            )
            context.insert(row)
            try context.save()
            Log.vectorstore.info("inserted vector dayKey=\(dayKey, privacy: .public)")
        } catch {
            Log.vectorstore.error("insert failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func nearestNeighbors(query: [Float], k: Int) throws -> [VectorNeighbor] {
        do {
            let rows = try context.fetch(FetchDescriptor<HealthVector>())
            let limit = max(0, k)
            guard limit > 0, !rows.isEmpty else { return [] }

            let scored = rows.compactMap { row -> VectorNeighbor? in
                guard let similarity = CosineSimilarity.score(query: query, candidate: row.vector) else {
                    return nil
                }
                return VectorNeighbor(summaryText: row.summaryText, similarity: similarity)
            }
            .sorted { $0.similarity > $1.similarity }

            let results = Array(scored.prefix(limit))
            Log.vectorstore.info("nearestNeighbors k=\(limit) hits=\(results.count, privacy: .public)")
            return results
        } catch {
            Log.vectorstore.error("nearestNeighbors failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func count() throws -> Int {
        do {
            let total = try context.fetchCount(FetchDescriptor<HealthVector>())
            Log.vectorstore.info("count=\(total, privacy: .public)")
            return total
        } catch {
            Log.vectorstore.error("count failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func deleteAll() throws {
        do {
            try context.delete(model: HealthVector.self)
            try context.save()
            Log.vectorstore.info("deleteAll completed")
        } catch {
            Log.vectorstore.error("deleteAll failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}

enum CosineSimilarity {
    static func score(query: [Float], candidate: [Float]) -> Float? {
        let length = query.count
        guard length > 0, length == candidate.count else { return nil }

        var dot: Float = 0
        var queryNormSquared: Float = 0
        var candidateNormSquared: Float = 0
        let n = vDSP_Length(length)

        query.withUnsafeBufferPointer { queryBuffer in
            candidate.withUnsafeBufferPointer { candidateBuffer in
                guard let queryBase = queryBuffer.baseAddress,
                      let candidateBase = candidateBuffer.baseAddress
                else { return }

                vDSP_dotpr(queryBase, 1, candidateBase, 1, &dot, n)
                vDSP_svesq(queryBase, 1, &queryNormSquared, n)
                vDSP_svesq(candidateBase, 1, &candidateNormSquared, n)
            }
        }

        let denominator = sqrtf(queryNormSquared) * sqrtf(candidateNormSquared)
        guard denominator > 0 else { return nil }
        return dot / denominator
    }
}
