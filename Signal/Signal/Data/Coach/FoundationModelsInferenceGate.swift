import Foundation

actor FoundationModelsInferenceGate {
    static let shared = FoundationModelsInferenceGate()

    private var responding = false

    func tryAcquire() -> Bool {
        guard !responding else { return false }
        responding = true
        return true
    }

    func release() {
        responding = false
    }

    func withExclusiveAccess<T>(
        _ operation: () async throws -> T
    ) async rethrows -> T? {
        guard tryAcquire() else { return nil }
        defer { release() }
        return try await operation()
    }
}
