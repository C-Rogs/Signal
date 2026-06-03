import os
import SwiftData
import SwiftUI

extension Notification.Name {
    static let signalDashboardBecameSelected = Notification.Name("signalDashboardBecameSelected")
}

struct DashboardView: View {
    @Binding var navigationPath: [DashboardDestination]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(UnitPreferences.self) private var unitPreferences
    @Query(sort: \Insight.createdAt, order: .reverse) private var insights: [Insight]
    @Query(sort: \DailyMetric.date, order: .forward) private var metrics: [DailyMetric]
    @Query(sort: \DailyNutrition.date, order: .forward) private var nutritionRows: [DailyNutrition]
    @Query(
        filter: #Predicate<WorkoutSession> { $0.endTime != nil },
        sort: \WorkoutSession.startTime,
        order: .reverse
    )
    private var completedWorkouts: [WorkoutSession]
    @State private var viewModel = DashboardViewModel()

    private var unitFormatter: DisplayUnitFormatter {
        DisplayUnitFormatter(preferences: unitPreferences)
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        dashboardRoot(viewModel: viewModel)
    }

    private func dashboardRoot(viewModel: DashboardViewModel) -> some View {
        Group {
            if showsEmptyDataState {
                fillHeightScroll(emptyDashboardContent)
            } else {
                fillHeightScroll(metricsDashboardContent(viewModel: viewModel))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            screenBackground.ignoresSafeArea()
        }
        .navigationTitle("Signal")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(navigationBarBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { dashboardToolbar }
        .accessibilityIdentifier("dashboardRoot")
        .onAppear(perform: handleAppear)
        .onChange(of: scenePhase) { _, phase in
            handleScenePhaseChange(phase)
        }
        .onReceive(NotificationCenter.default.publisher(for: .signalDashboardBecameSelected)) { _ in
            reloadViewModel()
        }
        .task(id: storeRefreshToken) {
            reloadViewModel()
        }
    }

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if healthKitManager.isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color("Primary"))
            }
        }
    }

    private func handleAppear() {
        reloadViewModel()
        Log.ui.info("dashboard appeared empty=\(showsEmptyDataState, privacy: .public)")
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active else { return }
        reloadViewModel()
    }

    private var navigationBarBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    private func reloadViewModel() {
        viewModel.reload(metrics: metrics, nutrition: nutritionRows)
    }

    private func fillHeightScroll<Content: View>(_ content: Content) -> some View {
        GeometryReader { geometry in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollContentBackground(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .refreshable {
                await refreshFromStore()
            }
        }
    }

    private var showsHealthSyncInEmptyState: Bool {
        healthKitManager.accessState == .ready && healthKitManager.isSyncing
    }

    private var latestCompletedWorkout: WorkoutSession? {
        completedWorkouts.first
    }

    @ViewBuilder
    private var emptyDashboardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            dashboardHeaderBanners

            if let workout = latestCompletedWorkout {
                recentWorkoutCard(workout)
            }

            if showsHealthSyncInEmptyState {
                healthSyncEmptyState
            } else {
                dashboardEmptyState
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func metricsDashboardContent(viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            dashboardHeaderBanners
            metricsContent(viewModel: viewModel)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var dashboardHeaderBanners: some View {
        if healthKitManager.accessState != .ready {
            HealthKitAccessBanner()
        }

        if let error = healthKitManager.lastSyncErrorMessage {
            syncErrorBanner(message: error)
        }
    }

    private var healthSyncEmptyState: some View {
        VStack(spacing: 16) {
            ProgressView("Syncing Health data...")
                .tint(Color("Primary"))
                .controlSize(.large)
            Text("Pull to refresh after sync finishes.")
                .font(.metadataCaption)
                .foregroundStyle(Color("TextSecondary"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func metricsContent(viewModel: DashboardViewModel) -> some View {
        DashboardWindowPicker(viewModel: viewModel)

        DashboardRecoveryCard(
            score: viewModel.recoveryScore,
            rollingMeans: viewModel.rollingMeans,
            window: viewModel.selectedWindow,
            hrvChartRange: viewModel.hrvChartRange
        )

        if let strain = viewModel.readinessFlags {
            DashboardStrainBanner(assessment: strain)
        }

        if let bannerInsight = topPriorityInsight {
            DashboardInsightBanner(insight: bannerInsight) {
                navigationPath.append(.insights)
            }
        }

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

        if hasExpandedSignals(viewModel: viewModel) {
            expandedSection(viewModel: viewModel)
        }
    }

    private var dashboardEmptyState: some View {
        ContentUnavailableView {
            Label("No recovery data yet", systemImage: "heart.text.square")
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
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(.top, 8)
    }

    private func recentWorkoutCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest workout")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))
            Text(session.title)
                .font(.headline)
                .foregroundStyle(Color("TextPrimary"))
            if let end = session.endTime {
                Text(end.formatted(date: .abbreviated, time: .shortened))
                    .font(.metadataCaption)
                    .foregroundStyle(Color("TextSecondary"))
            }
            Text("Saved in Train. Recovery charts need Apple Health daily metrics or an import from Profile.")
                .font(.metadataCaption)
                .foregroundStyle(Color("TextSecondary"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("Surface"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        !hasMeaningfulRecoveryData
    }

    private var topPriorityInsight: Insight? {
        let now = Date()
        return insights
            .filter { insight in
                guard !insight.isActioned else { return false }
                guard insight.severity == .alert || insight.severity == .warning else { return false }
                guard let expires = insight.expiresAt else { return true }
                return expires > now
            }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity == .alert
                }
                return lhs.createdAt > rhs.createdAt
            }
            .first
    }

    /// Dashboard charts need at least one populated value, not merely a `DailyMetric` row.
    /// Empty SwiftData rows (all fields nil) can exist after partial sync and previously forced the
    /// metrics layout with no visible series. Any one of the fields below is enough to show charts.
    private var hasMeaningfulRecoveryData: Bool {
        if nutritionRows.contains(where: hasMeaningfulNutrition) {
            return true
        }
        return metrics.contains(where: hasMeaningfulMetric)
    }

    private func hasMeaningfulMetric(_ metric: DailyMetric) -> Bool {
        metric.hrvSDNN_ms != nil
            || metric.restingHR != nil
            || metric.activeEnergy_kcal != nil
            || metric.sleepHours != nil
            || metric.bodyMassKg != nil
            || metric.stepCount != nil
            || metric.appleExerciseMinutes != nil
    }

    private func hasMeaningfulNutrition(_ row: DailyNutrition) -> Bool {
        row.dietaryEnergyKcal != nil || row.proteinG != nil
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
        let syncing = healthKitManager.isSyncing
        let workoutHead = completedWorkouts.first.map {
            String(describing: $0.persistentModelID)
        } ?? "none"
        let units = "\(unitPreferences.massUnit.rawValue)-\(unitPreferences.distanceUnit.rawValue)"
        return "\(metrics.count)-\(nutritionRows.count)-\(metricTail)-\(nutritionTail)-\(syncStamp)-\(syncing)-\(workoutHead)-\(units)"
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    private func hasExpandedSignals(viewModel: DashboardViewModel) -> Bool {
        !viewModel.bodyMassPoints.isEmpty
            || !viewModel.stepPoints.isEmpty
            || !viewModel.exercisePoints.isEmpty
            || viewModel.latestNutrition != nil
    }

    @ViewBuilder
    private func expandedSection(viewModel: DashboardViewModel) -> some View {
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
        reloadViewModel()
        Task {
            await DailyBriefingScheduler.shared.refreshSchedule(in: modelContext)
        }
    }
}

#Preview("Dashboard") {
    NavigationStack {
        DashboardView(navigationPath: .constant([]))
    }
    .environment(HealthKitManager(modelContainer: try! SignalModelContainer.make(inMemoryOnly: true)))
    .environment(UnitPreferences.shared)
    .modelContainer(try! SignalModelContainer.make(inMemoryOnly: true))
}
