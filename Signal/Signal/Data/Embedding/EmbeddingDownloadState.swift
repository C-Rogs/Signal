import Foundation
import Observation

enum EmbeddingLoadPhase: Equatable {
    case idle
    case downloading
    case ready
    case failed
}

@MainActor
@Observable
final class EmbeddingDownloadState {
    static let shared = EmbeddingDownloadState()

    private static let readyDefaultsKey = "embeddingInitialLoadComplete"

    var phase: EmbeddingLoadPhase = .idle
    var fractionCompleted: Double = 0
    var statusMessage = ""
    var errorMessage: String?
    private(set) var retryGeneration = 0

    var isDownloading: Bool { phase == .downloading }

    var isLoadingEmbeddings: Bool { phase == .downloading }

    private init() {
        if UserDefaults.standard.bool(forKey: Self.readyDefaultsKey) {
            phase = .ready
        }
    }

    func begin(message: String) {
        phase = .downloading
        fractionCompleted = 0
        statusMessage = message
        errorMessage = nil
    }

    func update(progress: Progress) {
        guard phase == .downloading else { return }
        if progress.totalUnitCount > 0 {
            fractionCompleted = progress.fractionCompleted
            statusMessage = "Downloading embedding model"
        } else if progress.completedUnitCount > 0 {
            statusMessage = "Downloading embedding model"
        }
    }

    func markReady() {
        phase = .ready
        fractionCompleted = 1
        statusMessage = ""
        errorMessage = nil
        UserDefaults.standard.set(true, forKey: Self.readyDefaultsKey)
    }

    func fail(_ message: String) {
        phase = .failed
        fractionCompleted = 0
        statusMessage = ""
        errorMessage = message
    }

    func requestRetry() {
        retryGeneration += 1
        phase = .idle
        errorMessage = nil
        statusMessage = ""
        fractionCompleted = 0
    }
}
