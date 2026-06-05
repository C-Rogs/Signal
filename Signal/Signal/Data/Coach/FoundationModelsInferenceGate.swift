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
}
