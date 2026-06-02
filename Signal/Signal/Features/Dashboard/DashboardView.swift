import os
import SwiftData
import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(HealthKitManager.self) private var healthKitManager
    @Query(sort: \DailyMetric.date, order: .forward) private var metrics: [DailyMetric]
    @Query(sort: \DailyNutrition.date, order: .forward) private var nutritionRows: [DailyNutrition]
    @State private var viewModel = DashboardViewModel()
    @State private var showImport = false
    @State private var showDiagnostics = false

    var body: some View {
        ZStack {
            screenBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DashboardWindowPicker(viewModel: viewModel)

                    DashboardRecoveryCard(
                        indicator: viewModel.recoveryIndicator,
                        rollingMeans: viewModel.rollingMeans,
                        window: viewModel.selectedWindow
                    )

                    DashboardMetricCard(
                        title: "HRV",
                        valueText: DashboardFormatting.hrv(viewModel.latestHRV),
                        subtitle: hrvSubtitle,
                        symbol: .heartVariability,
                        points: viewModel.hrvPoints,
                        valueStyle: .hrv,
                        tint: Color("Primary")
                    )

                    DashboardMetricCard(
                        title: "Resting HR",
                        valueText: DashboardFormatting.heartRate(viewModel.latestRestingHR),
                        subtitle: restingHRSubtitle,
                        symbol: .heartVariability,
                        points: viewModel.restingHRPoints,
                        valueStyle: .restingHR,
                        tint: Color("Negative")
                    )

                    HStack(spacing: 12) {
                        compactMetricCard(
                            title: "Active Energy",
                            value: DashboardFormatting.energy(viewModel.latestActiveEnergy),
                            symbol: .energy,
                            points: viewModel.activeEnergyPoints,
                            valueStyle: .activeEnergy,
                            tint: Color("Warning")
                        )
                        compactMetricCard(
                            title: "Sleep",
                            value: DashboardFormatting.sleep(viewModel.latestSleep),
                            symbol: .sleep,
                            points: viewModel.sleepPoints,
                            valueStyle: .sleepHours,
                            tint: Color("Primary")
                        )
                    }

                    if hasExpandedSignals {
                        expandedSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .refreshable {
                await refreshFromStore()
            }
        }
        .navigationTitle("Signal")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                diagnosticsButton
                importButton
            }
            ToolbarItem(placement: .topBarLeading) {
                if healthKitManager.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color("Primary"))
                }
            }
        }
        .onAppear {
            paintHostWindowForScheme()
            viewModel.reload(metrics: metrics, nutrition: nutritionRows)
            Log.ui.info("dashboard appeared")
        }
        .onChange(of: colorScheme) { _, _ in
            paintHostWindowForScheme()
        }
        .task(id: storeRefreshToken) {
            viewModel.reload(metrics: metrics, nutrition: nutritionRows)
        }
        .onChange(of: showImport) { _, isShowing in
            if !isShowing {
                viewModel.reload(metrics: metrics, nutrition: nutritionRows)
            }
        }
        .navigationDestination(isPresented: $showImport) {
            ImportView()
        }
        .navigationDestination(isPresented: $showDiagnostics) {
            DiagnosticsView()
        }
    }

    private var storeRefreshToken: String {
        let metricTail = metrics.suffix(3).map {
            "\($0.date.timeIntervalSince1970)-\($0.hrvSDNN_ms ?? 0)-\($0.restingHR ?? 0)"
        }.joined(separator: "|")
        let nutritionTail = nutritionRows.suffix(2).map {
            "\($0.date.timeIntervalSince1970)-\($0.dietaryEnergyKcal ?? 0)"
        }.joined(separator: "|")
        let syncStamp = healthKitManager.lastSyncFinishedAt?.timeIntervalSince1970 ?? 0
        return "\(metrics.count)-\(nutritionRows.count)-\(metricTail)-\(nutritionTail)-\(syncStamp)"
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    private var hasExpandedSignals: Bool {
        !viewModel.bodyMassPoints.isEmpty
            || !viewModel.stepPoints.isEmpty
            || !viewModel.exercisePoints.isEmpty
            || viewModel.latestNutrition != nil
    }

    @ViewBuilder
    private var expandedSection: some View {
        if !viewModel.bodyMassPoints.isEmpty {
            DashboardMetricCard(
                title: "Body Mass",
                valueText: DashboardFormatting.bodyMass(viewModel.latestBodyMass),
                subtitle: "Trend over \(viewModel.selectedWindow.label)",
                symbol: .bodyMass,
                points: viewModel.bodyMassPoints,
                valueStyle: .bodyMass,
                tint: Color("TextSecondary")
            )
        }

        if !viewModel.stepPoints.isEmpty || !viewModel.exercisePoints.isEmpty {
            DashboardMetricCard(
                title: "Movement",
                valueText: DashboardFormatting.steps(viewModel.latestSteps),
                subtitle: viewModel.activitySubtitle,
                symbol: .steps,
                points: viewModel.stepPoints,
                valueStyle: .steps,
                tint: Color("Positive")
            )
        }

        if let nutritionSubtitle = viewModel.nutritionSubtitle {
            DashboardMetricCard(
                title: "Nutrition",
                valueText: DashboardFormatting.calories(
                    viewModel.latestNutrition?.dietaryEnergyKcal
                ),
                subtitle: nutritionSubtitle,
                symbol: .nutrition,
                points: viewModel.nutritionEnergyPoints,
                valueStyle: .nutritionCalories,
                tint: Color("Warning")
            )
        }
    }

    private var hrvSubtitle: String? {
        guard let mean = viewModel.rollingMeans.mean(for: viewModel.selectedWindow).hrvSDNN else {
            return nil
        }
        return "\(Int(mean.rounded())) ms \(viewModel.selectedWindow.label) average"
    }

    private var restingHRSubtitle: String? {
        guard let mean = viewModel.rollingMeans.mean(for: viewModel.selectedWindow).restingHR else {
            return nil
        }
        return "\(Int(mean.rounded())) bpm \(viewModel.selectedWindow.label) average"
    }

    private func compactMetricCard(
        title: String,
        value: String,
        symbol: Symbol,
        points: [DashboardChartPoint],
        valueStyle: DashboardChartValueStyle,
        tint: Color
    ) -> some View {
        DashboardMetricCard(
            title: title,
            valueText: value,
            subtitle: nil,
            symbol: symbol,
            points: points,
            valueStyle: valueStyle,
            tint: tint
        )
    }

    private var diagnosticsButton: some View {
        Button("Diagnostics") {
            showDiagnostics = true
        }
        .font(.cardLabel)
        .foregroundStyle(Color("Primary"))
    }

    private var importButton: some View {
        Button("Import") {
            showImport = true
        }
        .font(.cardLabel)
        .foregroundStyle(Color("Primary"))
    }

    @MainActor
    private func refreshFromStore() async {
        Log.ui.info("dashboard pull-to-refresh")
        healthKitManager.syncNow()
        while healthKitManager.isSyncing {
            try? await Task.sleep(for: .milliseconds(200))
        }
        viewModel.reload(metrics: metrics, nutrition: nutritionRows)
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

#Preview("Dashboard") {
    NavigationStack {
        DashboardView()
    }
    .environment(HealthKitManager(modelContainer: try! SignalModelContainer.make(inMemoryOnly: true)))
    .modelContainer(try! SignalModelContainer.make(inMemoryOnly: true))
}
