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

enum TrainScenePhaseKeyboardPolicy {
    static func shouldReleaseSetFieldFocus(for phase: ScenePhase) -> Bool {
        phase == .inactive || phase == .background
    }

    static func shouldDismissKeyboardOnResume(for phase: ScenePhase) -> Bool {
        phase == .active
    }
}
