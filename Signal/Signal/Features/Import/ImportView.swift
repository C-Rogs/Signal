import os
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKitManager
    @State private var viewModel: ImportViewModel?

    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let viewModel {
                        HealthLiveSyncSection(healthKitManager: healthKitManager)
                        HealthImportSection(viewModel: viewModel)
                        HevyImportSection(viewModel: viewModel)
                    } else {
                        ProgressView()
                            .tint(Color("Primary"))
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel == nil {
                viewModel = ImportViewModel(modelContainer: modelContext.container)
            }
            viewModel?.resetStuckImportFlagsIfIdle()
            healthKitManager.refreshAccessState()
            Log.ui.info("import view appeared")
        }
    }
}

private struct HealthLiveSyncSection: View {
    @Bindable var healthKitManager: HealthKitManager
    @State private var showSyncHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("HealthKit live sync")
                    .font(.displayLarge)
                    .foregroundStyle(Color("TextPrimary"))

                Button {
                    showSyncHelp = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundStyle(Color("TextSecondary"))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("How Health sync works")
            }

            Text(
                "Anchored sync for Tier 1 metrics, nutrition, blood pressure, and Apple workouts. Background delivery updates the store after unlock."
            )
            .font(.cardLabel)
            .foregroundStyle(Color("TextSecondary"))

            Text(accessStatusText)
                .font(.cardLabel)
                .foregroundStyle(accessStatusColor)

            if healthKitManager.accessState != .ready {
                Text(syncGateHint)
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextSecondary"))
            }

            if let error = healthKitManager.lastSyncErrorMessage {
                Text(error)
                    .font(.cardLabel)
                    .foregroundStyle(.orange)
            }

            syncSummarySection

            HStack(spacing: 12) {
                if healthKitManager.accessState == .notDetermined {
                    Button("Allow Health access") {
                        Task {
                            await healthKitManager.requestAuthorization()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("Primary"))
                }

                Button("Sync now") {
                    healthKitManager.syncNow()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Primary"))
                .disabled(
                    healthKitManager.accessState != .ready
                        || healthKitManager.isSyncing
                )

                if healthKitManager.isSyncing {
                    ProgressView()
                        .tint(Color("Primary"))
                }
            }
        }
        .popover(isPresented: $showSyncHelp) {
            HealthSyncHelpPopover()
        }
    }

    private var syncGateHint: String {
        switch healthKitManager.accessState {
        case .unavailable:
            "Sync is unavailable on this device."
        case .notDetermined:
            "Use Allow Health access first. Sync stays off until you finish Apple's permission sheet."
        case .denied:
            "Grant access in Settings, then return here to sync."
        case .ready:
            ""
        }
    }

    private var accessStatusText: String {
        switch healthKitManager.accessState {
        case .unavailable:
            "Health data is not available on this device."
        case .notDetermined:
            "Health access not granted yet."
        case .ready:
            "Health access granted. Sync now is enabled."
        case .denied:
            "Health access appears denied. Open Settings > Health > Data Access & Devices > Signal."
        }
    }

    private var accessStatusColor: Color {
        switch healthKitManager.accessState {
        case .ready:
            Color("TextSecondary")
        case .unavailable, .denied:
            .orange
        case .notDetermined:
            Color("TextPrimary")
        }
    }

    @ViewBuilder
    private var syncSummarySection: some View {
        if let outcome = healthKitManager.lastSyncOutcome {
            VStack(alignment: .leading, spacing: 8) {
                Text("Last sync")
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextPrimary"))
                Text("No-op: \(outcome.noOp ? "yes" : "no")")
                Text("Days affected: \(outcome.affectedDayCount)")
                Text("Metrics written: \(outcome.metricsWritten)")
                Text("Vectors updated: \(outcome.vectorsWritten)")
                Text("Elapsed: \(String(format: "%.1f", outcome.elapsedSeconds)) s")
                if let finished = healthKitManager.lastSyncFinishedAt {
                    Text("Finished: \(finished.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            .font(.cardLabel)
            .foregroundStyle(Color("TextSecondary"))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("SurfaceElevated"))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct HealthSyncHelpPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How Health sync works")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))

            Group {
                helpRow(
                    title: "1. Allow Health access",
                    detail:
                        "Opens Apple's permission sheet. Turn on the categories you want Signal to read, then tap Allow. If the sheet closes before that, sync will find no data."
                )
                helpRow(
                    title: "2. Sync now",
                    detail:
                        "Enabled only after access is granted. Pulls new samples since your saved anchors, updates daily metrics and vectors on device."
                )
                helpRow(
                    title: "3. Background updates",
                    detail:
                        "While locked, Signal only marks data as dirty. After unlock or when you open the app, it runs the same sync without re-reading Health in the background observer."
                )
            }

            Text("Last sync below shows no-op when nothing changed since the previous anchor.")
                .font(.cardLabel)
                .foregroundStyle(Color("TextSecondary"))
        }
        .padding(20)
        .frame(maxWidth: 340, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }

    private func helpRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))
            Text(detail)
                .font(.cardLabel)
                .foregroundStyle(Color("TextSecondary"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct HealthImportSection: View {
    @Bindable var viewModel: ImportViewModel
    @State private var showFileImporter = false

    private static let allowedTypes: [UTType] = [
        .xml,
        .data,
        UTType(filenameExtension: "xml") ?? .xml,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Apple Health")
                .font(.displayLarge)
                .foregroundStyle(Color("TextPrimary"))

            Text("Unzip export.zip in Files, download export.xml fully (no cloud icon), then import. The file is streamed, not duplicated. Embeddings use MLX EmbeddingGemma on device and run after parsing.")
                .font(.cardLabel)
                .foregroundStyle(Color("TextSecondary"))

            if let error = viewModel.errorMessage,
               viewModel.isImportingHealth || viewModel.healthProgress.phase == .failed
            {
                Text(error)
                    .font(.cardLabel)
                    .foregroundStyle(.orange)
            }

            healthProgressSection
            healthSummarySection

            HStack(spacing: 12) {
                Button("Choose export.xml") {
                    Log.ui.info("health file picker requested")
                    showFileImporter = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Primary"))
                .disabled(viewModel.isImporting)

                if viewModel.isImportingHealth {
                    Button("Cancel") {
                        viewModel.cancelHealthImport()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.allowedTypes,
            allowsMultipleSelection: false
        ) { outcome in
            Log.ui.info("health file picker completed")
            switch outcome {
            case .success(let urls):
                guard let url = urls.first else {
                    viewModel.errorMessage = "No file was selected."
                    return
                }
                viewModel.importExportXML(from: url)
            case .failure(let error):
                Log.ui.error("health file picker failed: \(error.localizedDescription, privacy: .public)")
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var healthProgressSection: some View {
        if viewModel.isImportingHealth || viewModel.healthProgress.phase != .idle {
            VStack(alignment: .leading, spacing: 8) {
                Text("Health phase: \(viewModel.healthProgress.phase.rawValue)")
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextPrimary"))
                if viewModel.isImportingHealth {
                    ProgressView()
                        .tint(Color("Primary"))
                }
                if viewModel.healthProgress.phase == .parsing {
                    Text(
                        viewModel.healthProgress.recordsScanned == 0
                            ? "Streaming export.xml. Large files can take many minutes before the scanned count moves."
                            : "Parsing export.xml. Scanned count updates about every 10,000 records."
                    )
                    .foregroundStyle(Color("TextSecondary"))
                }
                Text("Records scanned: \(viewModel.healthProgress.recordsScanned)")
                Text("Tier 1 kept: \(viewModel.healthProgress.tier1RecordsKept)")
                Text("Days aggregated: \(viewModel.healthProgress.daysAggregated)")
                Text("Metrics written this run: \(viewModel.healthProgress.dailyMetricsWritten)")
                Text("Vectors written this run: \(viewModel.healthProgress.vectorsWritten)")
            }
            .font(.cardLabel)
            .foregroundStyle(Color("TextSecondary"))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("SurfaceElevated"))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private var healthSummarySection: some View {
        if let error = viewModel.errorMessage, !viewModel.isImporting {
            Text(error)
                .font(.cardLabel)
                .foregroundStyle(.orange)
        }

        if let result = viewModel.healthResult, !viewModel.isImportingHealth {
            VStack(alignment: .leading, spacing: 8) {
                Text("Health import summary")
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextPrimary"))
                Text("Records scanned: \(result.recordsScanned)")
                Text("Tier 1 kept: \(result.tier1RecordsKept)")
                Text("DailyMetric rows: \(result.dailyMetricCount)")
                Text("HealthVector rows: \(result.healthVectorCount)")
                Text("Elapsed: \(String(format: "%.1f", result.elapsedSeconds)) s")
                if let peak = result.peakMemoryBytes {
                    Text("Peak memory: \(String(format: "%.1f", Double(peak) / 1_048_576)) MB")
                }
                if !result.spotCheckSummaries.isEmpty {
                    Text("Spot-check (compare in Health app):")
                        .padding(.top, 8)
                    ForEach(result.spotCheckSummaries, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .font(.cardLabel)
            .foregroundStyle(Color("TextSecondary"))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("SurfaceElevated"))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct HevyImportSection: View {
    @Bindable var viewModel: ImportViewModel
    @State private var showFileImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Hevy CSV")
                .font(.displayLarge)
                .foregroundStyle(Color("TextPrimary"))

            Text("Extract HevyExport.zip in Files, then select the workout history CSV. Sets are stored structurally and enrich matching daily summaries and vectors.")
                .font(.cardLabel)
                .foregroundStyle(Color("TextSecondary"))

            hevyProgressSection
            hevySummarySection

            HStack(spacing: 12) {
                Button("Import Hevy CSV") {
                    Log.ui.info("Hevy file picker requested")
                    showFileImporter = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Primary"))
                .disabled(viewModel.isImporting)

                if viewModel.isImportingHevy {
                    Button("Cancel") {
                        viewModel.cancelHevyImport()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .data],
            allowsMultipleSelection: false
        ) { outcome in
            Log.ui.info("Hevy file picker completed")
            switch outcome {
            case .success(let urls):
                guard let url = urls.first else {
                    viewModel.errorMessage = "No file was selected."
                    return
                }
                viewModel.importHevyCSV(from: url)
            case .failure(let error):
                Log.ui.error("Hevy file picker failed: \(error.localizedDescription, privacy: .public)")
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var hevyProgressSection: some View {
        if viewModel.isImportingHevy || viewModel.hevyProgress.phase != .idle {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hevy phase: \(viewModel.hevyProgress.phase.rawValue)")
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextPrimary"))
                if viewModel.isImportingHevy {
                    ProgressView()
                        .tint(Color("Primary"))
                }
                Text("Rows parsed: \(viewModel.hevyProgress.rowsParsed)")
                Text("Sessions built: \(viewModel.hevyProgress.sessionsBuilt)")
                Text("Exercises persisted: \(viewModel.hevyProgress.exercisesPersisted)")
                Text("Sets persisted: \(viewModel.hevyProgress.setsPersisted)")
                Text("Days enriched: \(viewModel.hevyProgress.daysEnriched)")
                Text("Vectors updated: \(viewModel.hevyProgress.vectorsUpdated)")
            }
            .font(.cardLabel)
            .foregroundStyle(Color("TextSecondary"))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("SurfaceElevated"))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private var hevySummarySection: some View {
        if let result = viewModel.hevyResult, !viewModel.isImportingHevy {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hevy import summary")
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextPrimary"))
                Text("Rows parsed: \(result.rowsParsed)")
                Text("Sessions persisted: \(result.sessionsBuilt)")
                Text("Exercises persisted: \(result.exercisesPersisted)")
                Text("Sets persisted: \(result.setsPersisted)")
                Text("Days enriched: \(result.daysEnriched)")
                Text("Vectors updated this run: \(result.vectorsUpdatedThisRun)")
                Text("DailyMetric rows: \(result.dailyMetricCount)")
                Text("HealthVector rows: \(result.healthVectorCount)")
                Text("Elapsed: \(String(format: "%.1f", result.elapsedSeconds)) s")
                if !result.spotCheckSummaries.isEmpty {
                    Text("Spot-check workout days:")
                        .padding(.top, 8)
                    ForEach(result.spotCheckSummaries, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .font(.cardLabel)
            .foregroundStyle(Color("TextSecondary"))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("SurfaceElevated"))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
