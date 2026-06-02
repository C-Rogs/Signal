import os
import SwiftData
import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(UnitPreferences.self) private var unitPreferences
    @Query(sort: \DailyMetric.date, order: .forward) private var metrics: [DailyMetric]
    @Query(sort: \DailyNutrition.date, order: .forward) private var nutritionRows: [DailyNutrition]
    @State private var viewModel = DashboardViewModel()

    private var unitFormatter: DisplayUnitFormatter {
        DisplayUnitFormatter(preferences: unitPreferences)
    }

    var body: some View {
        ZStack {
            screenBackground
                .ignoresSafeArea()

            if showsInitialLoading {
                ProgressView("Loading dashboard...")
                    .tint(Color("Primary"))
            } else {
                dashboardScroll
            }
        }
        .navigationTitle("Signal")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
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
    }

    private var showsInitialLoading: Bool {
        metrics.isEmpty
            && nutritionRows.isEmpty
            && healthKitManager.accessState == .ready
            && healthKitManager.isSyncing
            && healthKitManager.lastSyncFinishedAt == nil
    }

    @ViewBuilder
    private var dashboardScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if healthKitManager.accessState != .ready {
                    HealthKitAccessBanner()
                }

                if let error = healthKitManager.lastSyncErrorMessage {
                    syncErrorBanner(message: error)
                }

                if showsEmptyDataState {
                    dashboardEmptyState
                } else {
                    metricsContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .refreshable {
            await refreshFromStore()
        }
    }

    @ViewBuilder
    private var metricsContent: some View {
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

    private var dashboardEmptyState: some View {
        ContentUnavailableView {
            Label("No data yet", systemImage: "heart.text.square")
        } description: {
            Text(emptyStateMessage)
        } actions: {
            if healthKitManager.accessState == .notDetermined {
                Button("Allow Health access") {
                    Task {
                        await healthKitManager.requestAuthorization()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Primary"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var emptyStateMessage: String {
        switch healthKitManager.accessState {
        case .ready:
            "Import an Apple Health export or Hevy CSV from Profile > Import, or pull to refresh after granting Health access."
        case .denied, .unavailable:
            "Import data from Profile > Import, or restore Health access to sync automatically."
        case .notDetermined:
            "Connect Apple Health or import a backup from Profile > Import to see recovery and trends."
        }
    }

    private var showsEmptyDataState: Bool {
        metrics.isEmpty && nutritionRows.isEmpty
    }

    private func syncErrorBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sync failed")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))
            Text(message)
                .font(.metadataCaption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry sync") {
                healthKitManager.syncNow()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("Primary"))
            .disabled(healthKitManager.isSyncing || healthKitManager.accessState != .ready)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color("SurfaceElevated"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var storeRefreshToken: String {
        let metricTail = metrics.suffix(3).map {
            "\($0.date.timeIntervalSince1970)-\($0.hrvSDNN_ms ?? 0)-\($0.restingHR ?? 0)"
        }.joined(separator: "|")
        let nutritionTail = nutritionRows.suffix(2).map {
            "\($0.date.timeIntervalSince1970)-\($0.dietaryEnergyKcal ?? 0)"
        }.joined(separator: "|")
        let syncStamp = healthKitManager.lastSyncFinishedAt?.timeIntervalSince1970 ?? 0
        let units = "\(unitPreferences.massUnit.rawValue)-\(unitPreferences.distanceUnit.rawValue)"
        return "\(metrics.count)-\(nutritionRows.count)-\(metricTail)-\(nutritionTail)-\(syncStamp)-\(units)"
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
                valueText: DashboardFormatting.bodyMass(
                    viewModel.latestBodyMass,
                    formatter: unitFormatter
                ),
                subtitle: "Trend over \(viewModel.selectedWindow.label)",
                symbol: .bodyMass,
                points: viewModel.bodyMassPoints,
                valueStyle: .bodyMass,
                tint: Color("TextSecondary")
            )
        }

        if !viewModel.stepPoints.isEmpty {
            DashboardMetricCard(
                title: "Steps",
                valueText: DashboardFormatting.steps(viewModel.latestSteps),
                subtitle: viewModel.stepsSubtitle,
                symbol: .steps,
                points: viewModel.stepPoints,
                valueStyle: .steps,
                tint: Color("Positive")
            )
        }

        if !viewModel.exercisePoints.isEmpty {
            DashboardMetricCard(
                title: "Exercise Minutes",
                valueText: DashboardFormatting.minutes(viewModel.latestExerciseMinutes),
                subtitle: viewModel.exerciseMinutesSubtitle,
                symbol: .energy,
                points: viewModel.exercisePoints,
                valueStyle: .exerciseMinutes,
                tint: Color("Warning")
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
        var parts: [String] = []
        if !viewModel.hrvHeadlineLabel.isEmpty, viewModel.hrvHeadlineLabel != "Today" {
            parts.append("\(viewModel.hrvHeadlineLabel) reading")
        }
        if let mean = viewModel.rollingMeans.mean(for: viewModel.selectedWindow).hrvSDNN {
            parts.append("\(Int(mean.rounded())) ms \(viewModel.selectedWindow.label) average")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

    @MainActor
    private func refreshFromStore() async {
        Log.ui.info("dashboard pull-to-refresh")
        healthKitManager.refreshAccessState()
        if healthKitManager.accessState == .ready {
            healthKitManager.syncNow()
            while healthKitManager.isSyncing {
                try? await Task.sleep(for: .milliseconds(200))
            }
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
    .environment(UnitPreferences.shared)
    .modelContainer(try! SignalModelContainer.make(inMemoryOnly: true))
}
