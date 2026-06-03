import os
import SwiftData
import SwiftUI

struct DiagnosticsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKitManager
    @State private var viewModel: DiagnosticsViewModel?
    @State private var showsDataQualityFlags = false

    var body: some View {
        ZStack {
            screenBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let viewModel {
                        storeHealthSection(viewModel: viewModel)
                        hrvAnalysisSection(viewModel: viewModel)
                        hrAttributionSection(viewModel: viewModel)
                        derivedMetricsSection(viewModel: viewModel)
                        syncSection(viewModel: viewModel)
                        importSummarySection
                        ragSmokeTestSection(viewModel: viewModel)
                        askCoachSection(viewModel: viewModel)
                        dayDumpSection(viewModel: viewModel)
                        retrievalUATSection(viewModel: viewModel)
                    } else {
                        ProgressView()
                            .tint(Color("Primary"))
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel == nil {
                viewModel = DiagnosticsViewModel(modelContainer: modelContext.container)
            }
            viewModel?.refresh(healthKitManager: healthKitManager)
            viewModel?.refreshCoachModelStatus()
            viewModel?.prewarmCoach()
            Log.ui.info("diagnostics view appeared")
        }
        .navigationDestination(isPresented: $showsDataQualityFlags) {
            if let viewModel {
                DataQualityFlagsListView(flags: viewModel.dataQualityFlagRows)
            }
        }
    }

    @ViewBuilder
    private func hrvAnalysisSection(viewModel: DiagnosticsViewModel) -> some View {
        elevatedCard {
            Text("HRV analysis")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))

            if let diagnostics = viewModel.recoveryDiagnostics {
                Text("Baseline mean ± SD: \(diagnostics.baselineMeanText) ± \(diagnostics.baselineSDText) ms")
                Text("Acute 7-day mean: \(diagnostics.acuteMeanText) ms")
                Text("Upper band: \(diagnostics.upperBandText) ms")
                Text("Lower band: \(diagnostics.lowerBandText) ms")
                Text("Classification: \(diagnostics.classificationLabel)")
                Text("Data points used: \(diagnostics.dataPointsUsed)")
                Text("RHR delta: \(formatDelta(viewModel.recoveryDiagnostics?.score.rhrDelta))")
                Text("Sleep delta: \(formatDelta(viewModel.recoveryDiagnostics?.score.sleepDelta)) h")
                Text(
                    "Score breakdown: HRV \(diagnostics.hrvTermText), RHR \(diagnostics.rhrTermText), sleep \(diagnostics.sleepTermText), total \(diagnostics.totalScoreText)"
                )
            } else {
                Text("No HRV history available.")
                    .foregroundStyle(Color("TextSecondary"))
            }
        }
    }

    private func formatDelta(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value))"
    }

    @ViewBuilder
    private func hrAttributionSection(viewModel: DiagnosticsViewModel) -> some View {
        elevatedCard {
            Text("HR attribution")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))

            let snapshot = viewModel.hrAttributionDiagnostics
            Text("SetHeartRateData rows: \(snapshot.totalRows)")
            Text("Sessions with full attribution: \(snapshot.fullSessionCount)")
            Text("Sessions with partial attribution: \(snapshot.partialSessionCount)")
        }
    }

    @ViewBuilder
    private func derivedMetricsSection(viewModel: DiagnosticsViewModel) -> some View {
        elevatedCard {
            if viewModel.isLoadingDerivedMetrics {
                ProgressView("Loading derived metrics...")
                    .tint(Color("Primary"))
            } else {
                DerivedMetricsDiagnosticsSection(
                    snapshot: viewModel.derivedMetricsSnapshot,
                    onShowDataQualityFlags: {
                        showsDataQualityFlags = true
                    }
                )
            }
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    @ViewBuilder
    private func storeHealthSection(viewModel: DiagnosticsViewModel) -> some View {
        elevatedCard {
            Text("Store health")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))

            metricLine("DailyMetric", count: viewModel.dailyMetricCount)
            Text("DailyMetric latest dayKey: \(viewModel.dailyMetricLatestDayKey)")
            Text("DailyMetric in last 7 days: \(viewModel.dailyMetricCountLast7Days)")
            metricLine("DailyNutrition", count: viewModel.dailyNutritionCount)
            metricLine("AppleWorkout", count: viewModel.appleWorkoutCount)
            metricLine("Hevy WorkoutSession", count: viewModel.hevyWorkoutSessionCount)
            metricLine("HealthVector", count: viewModel.healthVectorCount)
            Text("HealthVector latest dayKey: \(viewModel.healthVectorLatestDayKey)")
            Text("HealthVector in last 7 days: \(viewModel.healthVectorCountLast7Days)")
        }
    }

    @ViewBuilder
    private func syncSection(viewModel: DiagnosticsViewModel) -> some View {
        elevatedCard {
            Text("HealthKit sync")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))

            if let finished = healthKitManager.lastSyncFinishedAt {
                Text("Last sync: \(finished.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("Last sync: never")
            }

            if healthKitManager.isSyncing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color("Primary"))
                    Text("Sync in progress")
                }
            }

            if let error = healthKitManager.lastSyncErrorMessage {
                Text(error)
                    .foregroundStyle(.orange)
                Button("Retry sync") {
                    healthKitManager.syncNow()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Primary"))
                .disabled(healthKitManager.isSyncing || healthKitManager.accessState != .ready)
            }

            if let outcome = healthKitManager.lastSyncOutcome {
                Text("Last run no-op: \(outcome.noOp ? "yes" : "no")")
                Text("Days affected: \(outcome.affectedDayCount)")
                Text("Metrics written: \(outcome.metricsWritten)")
                Text("Vectors updated: \(outcome.vectorsWritten)")
                Text("Elapsed: \(String(format: "%.1f", outcome.elapsedSeconds)) s")

                Text("Samples fetched by type")
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextPrimary"))
                    .padding(.top, 8)

                ForEach(outcome.samplesFetchedByType.sorted(by: { $0.key < $1.key }), id: \.key) { typeIdentifier, count in
                    HStack(alignment: .firstTextBaseline) {
                        Text(typeIdentifier)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text("\(count)")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }

            Button("Reset sync anchors") {
                viewModel.resetSyncAnchors(healthKitManager: healthKitManager)
            }
            .buttonStyle(.bordered)
            .tint(Color("Primary"))
            .disabled(healthKitManager.isSyncing)

            if let message = viewModel.syncAnchorResetMessage {
                Text(message)
                    .foregroundStyle(Color("TextSecondary"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Sync anchors")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))
                .padding(.top, 8)

            ForEach(viewModel.syncAnchorRows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.typeIdentifier)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(row.statusLabel)
                }
            }
        }
    }

    @ViewBuilder
    private var importSummarySection: some View {
        elevatedCard {
            Text("Last import summary")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))

            if ImportSummaryStore.healthSummary == nil, ImportSummaryStore.hevySummary == nil {
                Text("No imports recorded on this install yet.")
            }

            if let summary = ImportSummaryStore.healthSummary {
                if let recorded = ImportSummaryStore.healthRecordedAt {
                    Text("Apple Health (\(recorded.formatted(date: .abbreviated, time: .shortened)))")
                        .foregroundStyle(Color("TextPrimary"))
                } else {
                    Text("Apple Health")
                        .foregroundStyle(Color("TextPrimary"))
                }
                Text(summary)
                    .font(.system(.caption, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let summary = ImportSummaryStore.hevySummary {
                if let recorded = ImportSummaryStore.hevyRecordedAt {
                    Text("Hevy (\(recorded.formatted(date: .abbreviated, time: .shortened)))")
                        .foregroundStyle(Color("TextPrimary"))
                        .padding(.top, ImportSummaryStore.healthSummary == nil ? 0 : 12)
                } else {
                    Text("Hevy")
                        .foregroundStyle(Color("TextPrimary"))
                        .padding(.top, ImportSummaryStore.healthSummary == nil ? 0 : 12)
                }
                Text(summary)
                    .font(.system(.caption, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func ragSmokeTestSection(viewModel: DiagnosticsViewModel) -> some View {
        elevatedCard {
            Text("RAG smoke test")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))

            Text("Embed your query with EmbeddingGemma (.query) and show top retrieved daily summaries from the on-device vector store.")
                .fixedSize(horizontal: false, vertical: true)

            TextField("Ask the store", text: Bindable(viewModel).queryText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button("Search") {
                Task {
                    await viewModel.runRetrievalSmokeTest()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("Primary"))
            .disabled(viewModel.isSearching || viewModel.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if viewModel.isSearching {
                ProgressView("Embedding and retrieving...")
                    .tint(Color("Primary"))
            }

            if let error = viewModel.searchError {
                Text(error)
                    .foregroundStyle(.orange)
            }

            if let footnote = viewModel.retrievalFootnote {
                Text(footnote)
                    .foregroundStyle(Color("TextSecondary"))
            }

            if !viewModel.searchResults.isEmpty {
                Text("Top \(viewModel.searchResults.count) matches")
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextPrimary"))
                    .padding(.top, 8)

                ForEach(viewModel.searchResults) { hit in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(hit.dayKey)
                                .font(.cardLabel)
                                .foregroundStyle(Color("TextPrimary"))
                            Spacer()
                            Text(hit.formattedScore)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color("Primary"))
                        }
                        Text(hit.summaryText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color("TextSecondary"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func askCoachSection(viewModel: DiagnosticsViewModel) -> some View {
        elevatedCard {
            Text("Ask coach")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))

            Text("Streams a Foundation Models answer using assembled profile, insights, metrics, RAG, and recent workouts. Build context first to confirm RAG without calling the model.")
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Foundation model")
                Spacer()
                Text(viewModel.coachModelStatusLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(viewModel.coachCanAsk ? Color("Primary") : .orange)
            }

            Button("Refresh model status") {
                viewModel.refreshCoachModelStatus()
            }
            .buttonStyle(.bordered)
            .tint(Color("Primary"))

            if let help = viewModel.coachModelHelpText {
                DisclosureGroup("Apple Intelligence troubleshooting") {
                    Text(help)
                        .font(.system(.caption, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            TextField("Ask the coach", text: Bindable(viewModel).coachQueryText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
                .autocorrectionDisabled()

            HStack(spacing: 12) {
                Button("Build context") {
                    viewModel.previewCoachContext()
                }
                .buttonStyle(.bordered)
                .tint(Color("Primary"))
                .disabled(
                    viewModel.coachIsBuildingContext
                        || viewModel.coachIsResponding
                        || viewModel.coachQueryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                Button("Ask") {
                    viewModel.askCoach()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Primary"))
                .disabled(
                    viewModel.coachIsResponding
                        || viewModel.coachIsBuildingContext
                        || viewModel.coachQueryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if viewModel.coachIsBuildingContext {
                ProgressView("Building context...")
                    .tint(Color("Primary"))
            }

            if viewModel.coachIsResponding {
                ProgressView("Coach is responding...")
                    .tint(Color("Primary"))
            }

            if let error = viewModel.coachError {
                Text(error)
                    .foregroundStyle(.orange)
            }

            if !viewModel.coachContextSummary.isEmpty {
                Text(viewModel.coachContextSummary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color("TextPrimary"))
                    .textSelection(.enabled)
            }

            if !viewModel.coachRAGPreview.isEmpty {
                DisclosureGroup("RAG retrieved") {
                    Text(viewModel.coachRAGPreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color("TextSecondary"))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            if !viewModel.coachResponseText.isEmpty {
                ScrollView {
                    Text(viewModel.coachResponseText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 240)
            }

            if !viewModel.coachContextPreview.isEmpty {
                DisclosureGroup("Full context sent") {
                    Text(viewModel.coachContextPreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color("TextSecondary"))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func dayDumpSection(viewModel: DiagnosticsViewModel) -> some View {
        elevatedCard {
            Text("Day dump")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))

            Text(
                "Dumps full HealthVector summaryText plus structured workout, nutrition, and metric fields for 2026-05-31, the latest nutrition day, and 2024-03-19."
            )
            .fixedSize(horizontal: false, vertical: true)

            Button("Dump day and copy report (\(viewModel.dayDumpReportCharacterCount) chars)") {
                viewModel.dumpDayAndCopyToPasteboard()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("Primary"))

            if let error = viewModel.dayDumpError {
                Text(error)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func retrievalUATSection(viewModel: DiagnosticsViewModel) -> some View {
        elevatedCard {
            Text("Retrieval UAT")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))

            Text("Runs the on-device embed and retrieve pipeline, then auto-grades top hits against SwiftData.")
                .fixedSize(horizontal: false, vertical: true)

            Button("Run all") {
                Task {
                    await viewModel.runAllRetrievalUAT()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("Primary"))
            .disabled(viewModel.isRunningUAT)

            HStack(spacing: 12) {
                Button("Copy report (\(viewModel.uatReportCharacterCount) chars)") {
                    viewModel.copyUATReportToPasteboard()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Primary"))
                .disabled(!viewModel.canCopyUATReport)

                ShareLink(item: viewModel.uatReportText) {
                    Text("Share report (\(viewModel.uatReportCharacterCount) chars)")
                }
                .buttonStyle(.bordered)
                .tint(Color("Primary"))
                .disabled(!viewModel.canCopyUATReport)
            }

            if viewModel.isRunningUAT {
                if let runningID = viewModel.uatRunningTestID,
                   let label = RetrievalUATCatalog.definition(id: runningID)?.label {
                    ProgressView("Running \(label)...")
                        .tint(Color("Primary"))
                } else {
                    ProgressView("Running UAT...")
                        .tint(Color("Primary"))
                }
            }

            if let error = viewModel.uatError {
                Text(error)
                    .foregroundStyle(.orange)
            }

            ForEach(RetrievalUATCatalog.all) { definition in
                uatCatalogRow(definition: definition, viewModel: viewModel)
            }

            if !viewModel.uatResults.isEmpty {
                Text("Results")
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextPrimary"))
                    .padding(.top, 8)

                ForEach(viewModel.uatResults) { result in
                    uatResultRow(result)
                }
            }
        }
    }

    private func uatCatalogRow(definition: RetrievalUATDefinition, viewModel: DiagnosticsViewModel) -> some View {
        let isRunning = viewModel.uatRunningTestID == definition.id
        let result = viewModel.uatResults.first { $0.definitionID == definition.id }

        return Button {
            Task {
                await viewModel.runRetrievalUAT(testID: definition.id)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(definition.label)
                        .foregroundStyle(Color("TextPrimary"))
                    Text(definition.query)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color("TextSecondary"))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else if let result {
                    Text(result.verdict.rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(uatVerdictColor(result.verdict))
                }
            }
            .padding(.top, 6)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRunningUAT)
    }

    private func uatResultRow(_ result: RetrievalUATResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(result.label)
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextPrimary"))
                Spacer()
                Text(result.verdict.rawValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(uatVerdictColor(result.verdict))
            }

            Text("mode=\(result.expectedMode.rawValue) det=\(result.detectedModeLabel)")
                .font(.system(.caption, design: .monospaced))

            Text("check \(result.checkLabel) \(result.ratioLabel)")
                .font(.system(.caption, design: .monospaced))

            if let structured = result.structuredAnswer {
                Text("structured (V2 target): \(structured)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color("TextSecondary"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = result.errorMessage {
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.orange)
            }

            ForEach(result.hits) { hit in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(hit.dayKey)
                            .foregroundStyle(Color("TextPrimary"))
                        Spacer()
                        Text(hit.formattedScore)
                            .foregroundStyle(Color("Primary"))
                    }
                    Text(hit.snippet)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color("TextSecondary"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 8)
    }

    private func uatVerdictColor(_ verdict: RetrievalUATVerdict) -> Color {
        switch verdict {
        case .pass:
            return .green
        case .fail:
            return .orange
        case .review:
            return Color("TextSecondary")
        case .limit:
            return .yellow
        }
    }

    private func metricLine(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)")
                .font(.system(.body, design: .monospaced))
        }
    }

    private func elevatedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .font(.cardLabel)
        .foregroundStyle(Color("TextSecondary"))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("SurfaceElevated"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
