import os
import SwiftUI

struct RootView: View {
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var downloadState = EmbeddingDownloadState.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background")
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Signal")
                        .font(.displayLarge)
                        .foregroundStyle(Color("TextPrimary"))

                    embeddingStatusLine

                    NavigationLink("Import Health Data") {
                        ImportView()
                    }
                    .font(.cardLabel)
                    .foregroundStyle(Color("Primary"))
                }

                if downloadState.isDownloading {
                    EmbeddingDownloadOverlay(state: downloadState)
                }
            }
        }
        .onAppear {
            Log.ui.info("Root view appeared")
            healthKitManager.refreshAccessState()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                healthKitManager.syncOnForegroundIfReady()
            }
        }
        .task(id: downloadState.retryGeneration) {
            guard !EmbeddingBackend.useNLContextualEmbeddingFallback else { return }
            await preloadEmbeddingModel()
        }
    }

    @ViewBuilder
    private var embeddingStatusLine: some View {
        switch downloadState.phase {
        case .idle:
            if !EmbeddingBackend.useNLContextualEmbeddingFallback {
                Text("Preparing on-device embeddings…")
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextSecondary"))
            }
        case .downloading:
            EmptyView()
        case .ready:
            Text("Embeddings ready")
                .font(.cardLabel)
                .foregroundStyle(Color("TextSecondary"))
        case .failed:
            VStack(spacing: 12) {
                Text(downloadState.errorMessage ?? "Embedding model could not load.")
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextSecondary"))
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    downloadState.requestRetry()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Primary"))
            }
            .padding(.horizontal, 24)
        }
    }

    private func preloadEmbeddingModel() async {
        do {
            _ = try await GemmaEmbeddingService.shared.ensureLoaded()
            Log.ui.info("embedding preload finished")
        } catch {
            Log.ui.error(
                "embedding preload failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}

private struct EmbeddingDownloadOverlay: View {
    let state: EmbeddingDownloadState

    var body: some View {
        VStack(spacing: 12) {
            if state.fractionCompleted > 0 {
                ProgressView(value: state.fractionCompleted)
                    .progressViewStyle(.linear)
                    .tint(Color("Primary"))
            } else {
                ProgressView()
                    .tint(Color("Primary"))
            }
            Text(state.statusMessage)
                .font(.cardLabel)
                .foregroundStyle(Color("TextSecondary"))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(Color("SurfaceElevated"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(32)
    }
}

#Preview("Light") {
    RootView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    RootView()
        .preferredColorScheme(.dark)
}
