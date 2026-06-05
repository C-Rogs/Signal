import SwiftData
import SwiftUI

struct ExerciseDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(UnitPreferences.self) private var unitPreferences

    let route: ExerciseDetailRoute

    @State private var viewModel: ExerciseDetailViewModel

    init(route: ExerciseDetailRoute) {
        self.route = route
        _viewModel = State(initialValue: ExerciseDetailViewModel(route: route))
    }

    private var formatter: DisplayUnitFormatter {
        DisplayUnitFormatter(preferences: unitPreferences)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Picker("Section", selection: $viewModel.selectedTab) {
                    ForEach(ExerciseDetailViewModel.Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                tabContent
            }
            .padding(TrainChrome.horizontalPadding)
        }
        .background(screenBackground.ignoresSafeArea())
        .navigationTitle(viewModel.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: route) {
            viewModel.load(modelContext: modelContext, unitPreferences: unitPreferences)
        }
    }

    private var screenBackground: Color {
        TrainChrome.screenBackground(colorScheme: colorScheme)
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExerciseIllustrationView(
                catalogEntry: viewModel.catalogEntry,
                title: viewModel.displayTitle,
                compact: false
            )
            if let catalog = viewModel.catalogEntry {
                MuscleChipRow(
                    primary: catalog.primaryMuscles,
                    secondary: catalog.secondaryMuscles
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .trainSurfaceCard()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .history:
            historyTab
        case .progress:
            progressTab
        case .howTo:
            howToTab
        }
    }

    @ViewBuilder
    private var historyTab: some View {
        if viewModel.historySessions.isEmpty {
            emptyState(
                title: "No history yet",
                message: "Log this exercise in a completed workout to see session history here."
            )
        } else {
            VStack(spacing: 10) {
                ForEach(viewModel.historySessions) { session in
                    NavigationLink(value: TrainRoute.history(session.sessionID)) {
                        historySessionCard(session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func historySessionCard(_ session: ExerciseHistorySession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.sessionTitle)
                    .font(.headline)
                    .foregroundStyle(Color("TextPrimary"))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color("TextSecondary"))
            }
            Text(session.date.formatted(date: .abbreviated, time: .shortened))
                .font(.metadataCaption)
                .foregroundStyle(Color("TextSecondary"))
            if session.setSummaries.isEmpty {
                Text("No sets logged")
                    .font(.body)
                    .foregroundStyle(Color("TextSecondary"))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(session.setSummaries.enumerated()), id: \.offset) { _, summary in
                        Text(summary)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(Color("TextPrimary"))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainSurfaceCard(cornerRadius: 12)
    }

    @ViewBuilder
    private var progressTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            TrainSectionHeader(title: "Estimated 1RM")
            DashboardSparklineChart(
                points: viewModel.e1rmChartPoints,
                valueStyle: .e1RM
            )
            .padding(14)
            .trainSurfaceCard()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                TrainStatCard(
                    title: "PR e1RM",
                    value: viewModel.prE1RMKg.map { formatter.formatMassKg($0) } ?? "—"
                )
                TrainStatCard(
                    title: "PR load",
                    value: prLoadLabel
                )
                TrainStatCard(
                    title: "Avg volume",
                    value: viewModel.averageWorkingSetVolumeKg.map {
                        "\(formatter.formatMassKg($0)) vol"
                    } ?? "—"
                )
            }
        }
    }

    private var prLoadLabel: String {
        guard let pr = viewModel.prLoad else { return "—" }
        return "\(formatter.formatMassKg(pr.weightKg)) × \(pr.reps)"
    }

    @ViewBuilder
    private var howToTab: some View {
        if let steps = viewModel.instructions, !steps.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.body.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color("Primary"))
                            .frame(width: 28, height: 28)
                            .background(Color("Primary").opacity(0.15))
                            .clipShape(Circle())
                        Text(step)
                            .font(.body)
                            .foregroundStyle(Color("TextPrimary"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .trainSurfaceCard(cornerRadius: 12)
                }
            }
        } else {
            emptyState(
                title: "No guide for this exercise yet",
                message: "How-to steps are available for exercises in your Hevy export. More guides may be added later."
            )
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "figure.strengthtraining.traditional")
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
