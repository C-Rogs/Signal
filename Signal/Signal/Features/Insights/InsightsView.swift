import os
import SwiftData
import SwiftUI

@MainActor
struct InsightsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Insight.createdAt, order: .reverse) private var allInsights: [Insight]
    @State private var showsHistory = false

    private var now: Date { Date() }

    private var activeInsights: [Insight] {
        allInsights.filter { isActive($0) && !$0.isActioned }
    }

    private var historyInsights: [Insight] {
        allInsights.filter { !isActive($0) || $0.isActioned }
    }

    private var displayedInsights: [Insight] {
        showsHistory ? historyInsights : activeInsights
    }

    private var groupedSections: [(InsightSeverity, [Insight])] {
        let order: [InsightSeverity] = [.alert, .warning, .info]
        return order.compactMap { severity in
            let rows = displayedInsights.filter { $0.severity == severity }
            guard !rows.isEmpty else { return nil }
            return (severity, rows)
        }
    }

    var body: some View {
        ZStack {
            screenBackground.ignoresSafeArea()

            if !showsHistory && activeInsights.isEmpty {
                ContentUnavailableView {
                    Label("No active insights", systemImage: "lightbulb")
                } description: {
                    Text("No active insights. Keep training and logging.")
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if showsHistory && historyInsights.isEmpty {
                        Text("No history yet.")
                            .foregroundStyle(Color("TextSecondary"))
                    }
                    ForEach(groupedSections, id: \.0) { severity, rows in
                        Section(severity.sectionTitle) {
                            ForEach(rows, id: \.dedupeKey) { insight in
                                insightRow(insight, dimmed: showsHistory)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        if !showsHistory {
                                            Button("Dismiss") {
                                                dismiss(insight)
                                            }
                                            .tint(Color("Negative"))
                                        }
                                    }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(showsHistory ? "Active" : "History") {
                    showsHistory.toggle()
                }
                .font(.cardLabel)
            }
        }
    }

    private func insightRow(_ insight: Insight, dimmed: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.severity.symbolName)
                .font(.title3)
                .foregroundStyle(insight.severity.tintColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 8) {
                Text(insight.bodyText)
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextPrimary"))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if let entity = insight.relatedEntity, !entity.isEmpty {
                        Text(entity)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color("SurfaceElevated"))
                            .clipShape(Capsule())
                            .foregroundStyle(Color("TextSecondary"))
                    }
                    Text(InsightFormatting.relativeDaysAgo(from: insight.createdAt, now: now))
                        .font(.caption)
                        .foregroundStyle(Color("TextSecondary"))
                }
            }
        }
        .opacity(dimmed ? 0.55 : 1)
        .listRowBackground(Color("Surface"))
    }

    private func dismiss(_ insight: Insight) {
        insight.isActioned = true
        try? modelContext.save()
        Log.ui.info("insight dismissed key=\(insight.dedupeKey, privacy: .public)")
    }

    private func isActive(_ insight: Insight) -> Bool {
        guard !insight.isActioned else { return false }
        guard let expires = insight.expiresAt else { return true }
        return expires > now
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }
}

private extension InsightSeverity {
    var sectionTitle: String {
        switch self {
        case .alert: return "Alerts"
        case .warning: return "Warnings"
        case .info: return "Info"
        }
    }

    var symbolName: String {
        switch self {
        case .alert: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .alert: return Color("Negative")
        case .warning: return Color("Warning")
        case .info: return Color("Primary")
        }
    }
}

#Preview {
    NavigationStack {
        InsightsView()
    }
    .modelContainer(try! SignalModelContainer.make(inMemoryOnly: true))
}
