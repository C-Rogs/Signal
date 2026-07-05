import SwiftUI
import UIKit

enum TrainKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

@MainActor
@Observable
final class TrainSetFieldFocusCoordinator {
    private(set) var dismissGeneration = 0
    private(set) var isEditing = false
    private var suppressNextCommit = false

    func requestDismiss() {
        suppressNextCommit = false
        dismissGeneration += 1
    }

    func prepareForSystemOverlay() {
        suppressNextCommit = true
    }

    func dismissForSystemOverlay() {
        suppressNextCommit = true
        dismissGeneration += 1
    }

    func consumeSuppressNextCommit() -> Bool {
        let suppress = suppressNextCommit
        suppressNextCommit = false
        return suppress
    }

    func noteEditingActive(_ active: Bool) {
        isEditing = active
        AppLifecycleBroker.shared.isLiveWorkoutSetFieldEditing = active
    }
}
