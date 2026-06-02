import os
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var downloadState = EmbeddingDownloadState.shared
    @State private var showImport = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Signal")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                embeddingStatusLine

                Button {
                    showImport = true
                } label: {
                    Text("Import Health Data")
                        .font(.cardLabel)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Primary"))
                .disabled(downloadState.isLoadingEmbeddings)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            paintHostWindowBlack()
            Log.ui.info("Root view appeared")
            healthKitManager.refreshAccessState()
            healthKitManager.activateBackgroundObserversIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                paintHostWindowBlack()
                healthKitManager.refreshAccessState()
                healthKitManager.syncOnForegroundIfReady()
            }
        }
        .fullScreenCover(isPresented: $showImport) {
            NavigationStack {
                ImportView()
            }
            .preferredColorScheme(.dark)
        }
        .task(id: downloadState.retryGeneration) {
            guard !EmbeddingBackend.useNLContextualEmbeddingFallback else { return }
            await runEmbeddingPreloadDeferred()
        }
    }

    @ViewBuilder
    private var embeddingStatusLine: some View {
        switch downloadState.phase {
        case .idle, .downloading:
            EmbeddingLoadProgressView(
                fractionCompleted: downloadState.fractionCompleted,
                message: downloadState.statusMessage.isEmpty
                    ? "Preparing on-device embeddings"
                    : downloadState.statusMessage
            )
        case .ready:
            Text("Embeddings ready")
                .font(.cardLabel)
                .foregroundStyle(.white.opacity(0.72))
        case .failed:
            VStack(spacing: 12) {
                Text(downloadState.errorMessage ?? "Embedding model could not load.")
                    .font(.cardLabel)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    downloadState.requestRetry()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Primary"))
            }
        }
    }

    private func runEmbeddingPreloadDeferred() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(500))
        downloadState.begin(message: "Preparing on-device embeddings")
        Log.ui.info("embedding preload started")
        do {
            _ = try await GemmaEmbeddingService.shared.ensureLoaded()
            Log.ui.info("embedding preload finished")
        } catch {
            Log.ui.error(
                "embedding preload failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func paintHostWindowBlack() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }
        for window in scene.windows {
            window.backgroundColor = .black
        }
    }
}

private struct EmbeddingLoadProgressView: View {
    let fractionCompleted: Double
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            if fractionCompleted > 0 {
                ProgressView(value: fractionCompleted)
                    .progressViewStyle(.linear)
                    .tint(Color("Primary"))
                    .frame(height: 6)
                Text("\(Int(fractionCompleted * 100))%")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                ProgressView()
                    .controlSize(.regular)
                    .tint(Color("Primary"))
                    .frame(width: 28, height: 28)
            }
            Text(message)
                .font(.cardLabel)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
            Text("First launch can take a few minutes. The app is still working.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 360)
    }
}

#Preview("Dark") {
    RootView()
        .environment(HealthKitManager(modelContainer: try! SignalModelContainer.make(inMemoryOnly: true)))
}
