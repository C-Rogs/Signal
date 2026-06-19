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
enum TrainApplicationLifecycle {
    static var testingIsInTrueBackground: Bool?

    private(set) static var isInTrueBackground = false
    private(set) static var trueBackgroundGeneration = 0
    private(set) static var lastDidEnterBackgroundAt: Date?
    private(set) static var lastWillEnterForegroundAt: Date?
    private static var observersInstalled = false

    static var isWorkoutOverlayPresented = false
    static var isLiveWorkoutSetFieldEditing = false
    static var isLiveWorkoutSessionInProgress = false
    private(set) static var isKeyboardVisible = false

    static var resolvedIsInTrueBackground: Bool {
        testingIsInTrueBackground ?? isInTrueBackground
    }

    static func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        let center = NotificationCenter.default
        center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let msSinceForeground = Self.millisecondsSince(lastWillEnterForegroundAt)
                TrainWorkoutDiagnostics.record(
                    "appDidBecomeActive uiState=\(UIApplication.shared.applicationState.rawValue) workoutViewing=\(isWorkoutOverlayPresented) editing=\(isLiveWorkoutSetFieldEditing) keyboardVisible=\(isKeyboardVisible) msSinceWillEnterForeground=\(msSinceForeground)"
                )
            }
        }
        center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                TrainWorkoutDiagnostics.record(
                    "appWillResignActive uiState=\(UIApplication.shared.applicationState.rawValue) editing=\(isLiveWorkoutSetFieldEditing) workoutViewing=\(isWorkoutOverlayPresented) keyboardVisible=\(isKeyboardVisible)"
                )
            }
        }
        let keyboardCenter = NotificationCenter.default
        keyboardCenter.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                isKeyboardVisible = true
            }
        }
        keyboardCenter.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                isKeyboardVisible = false
            }
        }
        center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                isInTrueBackground = true
                trueBackgroundGeneration += 1
                lastDidEnterBackgroundAt = Date()
                TrainWorkoutDiagnostics.record(
                    "appDidEnterBackground gen=\(trueBackgroundGeneration) uiState=\(UIApplication.shared.applicationState.rawValue) workoutViewing=\(isWorkoutOverlayPresented) editing=\(isLiveWorkoutSetFieldEditing)"
                )
                if isWorkoutOverlayPresented {
                    TrainKeyboard.dismiss()
                    Task {
                        await LiveWorkoutWatchBridge.shared.suspendForAppBackground()
                    }
                }
            }
        }
        center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                isInTrueBackground = false
                lastWillEnterForegroundAt = Date()
                let msSinceBackground = Self.millisecondsSince(lastDidEnterBackgroundAt)
                TrainWorkoutDiagnostics.record(
                    "appWillEnterForeground uiState=\(UIApplication.shared.applicationState.rawValue) workoutViewing=\(isWorkoutOverlayPresented) bgGen=\(trueBackgroundGeneration) msSinceBackground=\(msSinceBackground)"
                )
            }
        }
    }

    private static func millisecondsSince(_ date: Date?) -> String {
        guard let date else { return "na" }
        return String(Int(Date().timeIntervalSince(date) * 1000))
    }

    static func shouldDeferForegroundHousekeeping(workoutPresented: Bool) -> Bool {
        workoutPresented || isWorkoutOverlayPresented || isLiveWorkoutSetFieldEditing
    }

    static func shouldSkipDeferredSystemWork() -> Bool {
        isWorkoutOverlayPresented || isLiveWorkoutSetFieldEditing || isLiveWorkoutSessionInProgress
    }

    static func setLastDidEnterBackgroundForTesting(_ date: Date?) {
        lastDidEnterBackgroundAt = date
    }

    static func setLastWillEnterForegroundForTesting(_ date: Date?) {
        lastWillEnterForegroundAt = date
    }

    static var recentlyEnteredForeground: Bool {
        guard let lastWillEnterForegroundAt else { return false }
        return Date().timeIntervalSince(lastWillEnterForegroundAt) < 1.0
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
        TrainApplicationLifecycle.isLiveWorkoutSetFieldEditing = active
    }
}
