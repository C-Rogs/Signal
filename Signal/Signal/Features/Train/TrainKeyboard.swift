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
    /// App switcher is `.inactive`; releasing focus there corrupts SwiftUI set rows. Wait for `.background`.
    static func shouldReleaseSetFieldFocus(for phase: ScenePhase) -> Bool {
        phase == .background
    }
}
