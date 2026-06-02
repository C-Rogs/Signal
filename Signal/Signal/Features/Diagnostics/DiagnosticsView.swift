import os
import SwiftData
import SwiftUI

struct DiagnosticsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKitManager
    @State private var viewModel: DiagnosticsViewModel?

    var body: some View {
        ZStack {
            screenBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let viewModel {
                        storeHealthSection(viewModel: viewModel)
                        syncSection(viewModel: viewModel)
                        importSummarySection
                        ragSmokeTestSection(viewModel: viewModel)
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
            Log.ui.info("diagnostics view appeared")
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
            }

            if let outcome = healthKitManager.lastSyncOutcome {
                Text("Last run no-op: \(outcome.noOp ? "yes" : "no")")
                Text("Days affected: \(outcome.affectedDayCount)")
                Text("Metrics written: \(outcome.metricsWritten)")
                Text("Vectors updated: \(outcome.vectorsWritten)")
                Text("Elapsed: \(String(format: "%.1f", outcome.elapsedSeconds)) s")
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
