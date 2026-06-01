import os
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ImportViewModel?
    @State private var showFileImporter = false

    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Import Apple Health")
                        .font(.displayLarge)
                        .foregroundStyle(Color("TextPrimary"))

                    Text("Extract export.zip in Files, then select export.xml. Parsing runs on device; embeddings require Apple Intelligence hardware.")
                        .font(.cardLabel)
                        .foregroundStyle(Color("TextSecondary"))

                    if let viewModel {
                        progressSection(viewModel)
                        summarySection(viewModel)
                    }

                    HStack(spacing: 12) {
                        Button("Choose export.xml") {
                            showFileImporter = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("Primary"))
                        .disabled(viewModel?.isImporting == true)

                        if viewModel?.isImporting == true {
                            Button("Cancel") {
                                viewModel?.cancelImport()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.xml],
            allowsMultipleSelection: false
        ) { outcome in
            guard let viewModel else { return }
            switch outcome {
            case .success(let urls):
                guard let url = urls.first else { return }
                viewModel.importExportXML(from: url)
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ImportViewModel(modelContainer: modelContext.container)
            }
            Log.ui.info("import view appeared")
        }
    }

    @ViewBuilder
    private func progressSection(_ viewModel: ImportViewModel) -> some View {
        if viewModel.isImporting || viewModel.progress.phase != .idle {
            VStack(alignment: .leading, spacing: 8) {
                Text("Phase: \(viewModel.progress.phase.rawValue)")
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextPrimary"))
                if viewModel.isImporting {
                    ProgressView()
                        .tint(Color("Primary"))
                }
                Text("Records scanned: \(viewModel.progress.recordsScanned)")
                Text("Tier 1 kept: \(viewModel.progress.tier1RecordsKept)")
                Text("Days aggregated: \(viewModel.progress.daysAggregated)")
                Text("Metrics written: \(viewModel.progress.dailyMetricsWritten)")
                Text("Vectors written: \(viewModel.progress.vectorsWritten)")
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
    private func summarySection(_ viewModel: ImportViewModel) -> some View {
        if let error = viewModel.errorMessage {
            Text(error)
                .font(.cardLabel)
                .foregroundStyle(.orange)
        }

        if let result = viewModel.result, !viewModel.isImporting {
            VStack(alignment: .leading, spacing: 8) {
                Text("Import summary")
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
