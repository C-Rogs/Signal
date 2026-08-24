import os
import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LiveWorkoutCoordinator.self) private var workoutCoordinator
    @Environment(AppLifecycleBroker.self) private var lifecycleBroker
    @Bindable private var downloadState = EmbeddingDownloadState.shared

    var body: some View {
        Group {
            if downloadState.phase == .ready || EmbeddingBackend.useNLContextualEmbeddingFallback {
                MainTabView()
            } else {
                embeddingGate
            }
        }
        .onAppear {
            paintHostWindowForScheme()
            workoutCoordinator.markReadyForScenePhaseRefresh()
            TrainWorkoutDiagnostics.beginSession("appLaunch")
            Log.ui.info("Root view appeared")
            healthKitManager.refreshAccessState()
            healthKitManager.activateBackgroundObserversIfNeeded()
        }
        .onChange(of: scenePhase) { previousPhase, phase in
            TrainWorkoutDiagnostics.record(
                "root scenePhase=\(phase) presented=\(workoutCoordinator.presentedWorkoutSessionID != nil) viewing=\(workoutCoordinator.isViewingActiveWorkout) bgGen=\(lifecycleBroker.trueBackgroundGeneration)"
            )
            if phase == .background, workoutCoordinator.presentedWorkoutSessionID == nil {
                try? modelContext.save()
            }
            workoutCoordinator.handleRootScenePhaseChange(from: previousPhase, to: phase)
            if phase == .active {
                runRootForegroundWork()
            }
        }
        .onChange(of: colorScheme) { _, _ in
            paintHostWindowForScheme()
        }
        .task(id: embeddingPreloadTaskID) {
            guard scenePhase == .active else { return }
            guard downloadState.phase != .ready else { return }
            guard !EmbeddingBackend.useNLContextualEmbeddingFallback else { return }
            await runEmbeddingPreloadDeferred()
        }
    }

    @ViewBuilder
    private var embeddingGate: some View {
        ZStack {
            gateBackground
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Signal")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(gatePrimaryText)

                embeddingStatusLine
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var gateBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    private var gatePrimaryText: Color {
        colorScheme == .dark ? .white : Color("TextPrimary")
    }

    @ViewBuilder
    private var embeddingStatusLine: some View {
        switch downloadState.phase {
        case .idle, .downloading:
            EmbeddingLoadProgressView(
                fractionCompleted: downloadState.fractionCompleted,
                message: downloadState.statusMessage.isEmpty
                    ? "Preparing on-device embeddings"
                    : downloadState.statusMessage,
                colorScheme: colorScheme
            )
        case .ready:
            ProgressView("Opening Signal...")
                .controlSize(.regular)
                .tint(Color("Primary"))
        case .failed:
            VStack(spacing: 12) {
                Text(downloadState.errorMessage ?? "Embedding model could not load.")
                    .font(.cardLabel)
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.72) : Color("TextSecondary"))
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    downloadState.requestRetry()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Primary"))
            }
        }
    }

    private var embeddingPreloadTaskID: String {
        if downloadState.phase == .ready {
            return "ready-\(downloadState.retryGeneration)"
        }
        return "\(downloadState.retryGeneration)-\(scenePhase == .active ? "active" : "inactive")"
    }

    private func runEmbeddingPreloadDeferred() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(500))
        guard await MainActor.run(body: { EmbeddingRunPolicy.mayUseMetal }) else { return }
        guard !EmbeddingBackend.useNLContextualEmbeddingFallback else {
            downloadState.markReady()
            return
        }
        Log.ui.info("embedding preload started")
        do {
            _ = try await GemmaEmbeddingService.shared.ensureLoaded()
            downloadState.markReady()
            TrainWorkoutDiagnostics.recordMemory("embeddingPreloadReady")
            Log.ui.info("embedding preload finished")
        } catch EmbeddingServiceError.metalWorkNotPermittedInBackground {
            Log.ui.info("embedding preload paused; app is not active")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            downloadState.fail(message.isEmpty ? "Embedding model could not load." : message)
            Log.ui.error(
                "embedding preload failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func runRootForegroundWork() {
        EmbeddingRunPolicy.applicationDidBecomeActive()
        paintHostWindowForScheme()
        if workoutCoordinator.isViewingActiveWorkout {
            TrainWorkoutDiagnostics.record("root skipDeferredForegroundWork workoutViewing=true")
            return
        }
        if workoutCoordinator.activeSession != nil {
            TrainWorkoutDiagnostics.record("root skipDeferredForegroundWork activeSessionMinimized=true")
            return
        }
        performDeferredRootForegroundWork()
    }

    private func performDeferredRootForegroundWork() {
        guard !healthKitManager.isSyncing else {
            TrainWorkoutDiagnostics.record("root skipDeferredForegroundWork healthKitSyncing=true")
            return
        }
        healthKitManager.refreshAccessState()
        healthKitManager.syncOnForegroundIfReady()
        WatchConnectivityService.shared.retryPendingPush()
        LiveWorkoutWatchBridge.shared.retryPendingOutboundTelemetry()
        runReflectionIfForegroundDue()
        refreshDailyBriefingScheduleIfNeeded()
    }

    private func runReflectionIfForegroundDue() {
        guard !lifecycleBroker.resolvedIsInTrueBackground else { return }
        guard ReflectionSchedule.shouldRunOnForeground() else { return }
        let context = modelContext
        Task {
            guard await ReflectionEngine.shared.mayStartReflection() else { return }
            await ReflectionEngine.shared.runReflection(in: context)
            await DailyBriefingScheduler.shared.refreshSchedule(in: context)
        }
    }

    private static var lastBriefingRefreshAt: Date?

    private func refreshDailyBriefingScheduleIfNeeded() {
        let now = Date()
        if let last = Self.lastBriefingRefreshAt, now.timeIntervalSince(last) < 900 {
            return
        }
        Self.lastBriefingRefreshAt = now
        refreshDailyBriefingSchedule()
    }

    private func refreshDailyBriefingSchedule() {
        let context = modelContext
        Task {
            await DailyBriefingScheduler.shared.refreshSchedule(in: context)
        }
    }

    private func paintHostWindowForScheme() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }
        let color: UIColor = colorScheme == .dark ? .black : .white
        for window in scene.windows {
            window.backgroundColor = color
        }
    }
}

private struct EmbeddingLoadProgressView: View {
    let fractionCompleted: Double
    let message: String
    let colorScheme: ColorScheme

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.72) : Color("TextSecondary")
    }

    private var tertiaryText: Color {
        colorScheme == .dark ? .white.opacity(0.45) : Color("TextSecondary").opacity(0.8)
    }

    var body: some View {
        VStack(spacing: 10) {
            if fractionCompleted > 0 {
                ProgressView(value: fractionCompleted)
                    .progressViewStyle(.linear)
                    .tint(Color("Primary"))
                    .frame(height: 6)
                Text("\(Int(fractionCompleted * 100))%")
                    .font(.caption)
                    .foregroundStyle(tertiaryText)
            } else {
                ProgressView()
                    .controlSize(.regular)
                    .tint(Color("Primary"))
                    .frame(width: 28, height: 28)
            }
            Text(message)
                .font(.cardLabel)
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.center)
            Text("First launch can take a few minutes. The app is still working.")
                .font(.caption)
                .foregroundStyle(tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 360)
    }
}

#Preview("Dark") {
    RootView()
        .environment(HealthKitManager(modelContainer: try! SignalModelContainer.make(inMemoryOnly: true)))
        .environment(UnitPreferences.shared)
        .environment(NotificationPreferences.shared)
        .preferredColorScheme(.dark)
}
