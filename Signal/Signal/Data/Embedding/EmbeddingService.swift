import Foundation
import UIKit

enum EmbeddingKind: Sendable, Equatable {
    case document
    case query
}

extension EmbeddingKind {
    func prompted(_ text: String) -> String {
        switch self {
        case .document:
            "title: none | text: \(text)"
        case .query:
            "task: search result | query: \(text)"
        }
    }
}

enum EmbeddingServiceError: Error, Sendable {
    case dimensionMismatch(expected: Int, actual: Int)
    case modelNotLoaded
    case contextualEmbeddingUnavailable
    case assetsUnavailable
    case metalWorkNotPermittedInBackground
}

protocol EmbeddingService: Sendable {
    var outputDimension: Int { get }

    func embed(_ text: String, kind: EmbeddingKind) async throws -> [Float]

    func embedBatch(_ texts: [String], kind: EmbeddingKind) async throws -> [[Float]]
}

enum EmbeddingRunPolicy {
    @MainActor
    private static var metalWaiters: [CheckedContinuation<Void, Never>] = []

    @MainActor
    static var mayUseMetal: Bool {
        if EmbeddingBackend.useDeterministicTestEmbedding {
            return true
        }
        return UIApplication.shared.applicationState == .active
    }

    @MainActor
    static func applicationDidBecomeActive() {
        guard mayUseMetal else { return }
        let waiters = metalWaiters
        metalWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    static func waitUntilMayUseMetal() async {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                if mayUseMetal {
                    continuation.resume()
                } else {
                    metalWaiters.append(continuation)
                }
            }
        }
    }
}

enum EmbeddingBackend {
    static var useNLContextualEmbeddingFallback = false
    static var useDeterministicTestEmbedding = false

    static func makeService() -> any EmbeddingService {
        if useDeterministicTestEmbedding {
            DeterministicTestEmbeddingService.shared
        } else if useNLContextualEmbeddingFallback {
            NLEmbeddingService.shared
        } else {
            GemmaEmbeddingService.shared
        }
    }
}
