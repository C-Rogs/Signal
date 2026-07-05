import SwiftUI
import UIKit

@MainActor
@Observable
final class AppLifecycleBroker {
    static let shared = AppLifecycleBroker()

    var testingIsInTrueBackground: Bool?

    private(set) var isInTrueBackground = false
    private(set) var trueBackgroundGeneration = 0
    private(set) var lastDidEnterBackgroundAt: Date?
    private(set) var lastWillEnterForegroundAt: Date?
    private(set) var backgroundFocusDismissGeneration = 0
    private(set) var isKeyboardVisible = false

    var isWorkoutOverlayPresented = false
    var isLiveWorkoutSetFieldEditing = false
    var isLiveWorkoutSessionInProgress = false

    private var observersInstalled = false
    private weak var workoutCoordinator: LiveWorkoutCoordinator?

    var resolvedIsInTrueBackground: Bool {
        testingIsInTrueBackground ?? isInTrueBackground
    }

    var recentlyEnteredForeground: Bool {
        guard let lastWillEnterForegroundAt else { return false }
        return Date().timeIntervalSince(lastWillEnterForegroundAt) < 1.0
    }

    var pathPopGraceActive: Bool {
        guard let lastWillEnterForegroundAt else { return false }
        return Date().timeIntervalSince(lastWillEnterForegroundAt) < 2.5
    }

    private init() {}

    func configure(workoutCoordinator: LiveWorkoutCoordinator) {
        self.workoutCoordinator = workoutCoordinator
    }

    func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        let center = NotificationCenter.default
        center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let msSinceForeground = Self.millisecondsSince(self.lastWillEnterForegroundAt)
                TrainWorkoutDiagnostics.record(
                    "appDidBecomeActive uiState=\(UIApplication.shared.applicationState.rawValue) workoutViewing=\(self.isWorkoutOverlayPresented) editing=\(self.isLiveWorkoutSetFieldEditing) keyboardVisible=\(self.isKeyboardVisible) msSinceWillEnterForeground=\(msSinceForeground)"
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
                    "appWillResignActive uiState=\(UIApplication.shared.applicationState.rawValue) editing=\(self.isLiveWorkoutSetFieldEditing) workoutViewing=\(self.isWorkoutOverlayPresented) keyboardVisible=\(self.isKeyboardVisible)"
                )
            }
        }
        center.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                self.isKeyboardVisible = true
            }
        }
        center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                self.isKeyboardVisible = false
            }
        }
        center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                self.handleDidEnterBackground()
            }
        }
        center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                self.handleWillEnterForeground()
            }
        }
    }

    private func handleDidEnterBackground() {
        isInTrueBackground = true
        trueBackgroundGeneration += 1
        lastDidEnterBackgroundAt = Date()
        TrainWorkoutDiagnostics.record(
            "appDidEnterBackground gen=\(trueBackgroundGeneration) uiState=\(UIApplication.shared.applicationState.rawValue) workoutViewing=\(isWorkoutOverlayPresented) editing=\(isLiveWorkoutSetFieldEditing)"
        )
        guard isWorkoutOverlayPresented else { return }
        TrainKeyboard.dismiss()
        backgroundFocusDismissGeneration += 1
        workoutCoordinator?.noteWorkoutViewDisappearedWhilePresented(scenePhase: .background)
        Task {
            await LiveWorkoutWatchBridge.shared.suspendForAppBackground()
        }
    }

    private func handleWillEnterForeground() {
        isInTrueBackground = false
        lastWillEnterForegroundAt = Date()
        let msSinceBackground = Self.millisecondsSince(lastDidEnterBackgroundAt)
        TrainWorkoutDiagnostics.record(
            "appWillEnterForeground uiState=\(UIApplication.shared.applicationState.rawValue) workoutViewing=\(isWorkoutOverlayPresented) bgGen=\(trueBackgroundGeneration) msSinceBackground=\(msSinceBackground)"
        )
    }

    func shouldDeferForegroundHousekeeping(workoutPresented: Bool) -> Bool {
        workoutPresented || isWorkoutOverlayPresented || isLiveWorkoutSetFieldEditing
    }

    func shouldSkipDeferredSystemWork() -> Bool {
        isWorkoutOverlayPresented || isLiveWorkoutSetFieldEditing || isLiveWorkoutSessionInProgress
    }

    func setLastDidEnterBackgroundForTesting(_ date: Date?) {
        lastDidEnterBackgroundAt = date
    }

    func setLastWillEnterForegroundForTesting(_ date: Date?) {
        lastWillEnterForegroundAt = date
    }

    private static func millisecondsSince(_ date: Date?) -> String {
        guard let date else { return "na" }
        return String(Int(Date().timeIntervalSince(date) * 1000))
    }
}
