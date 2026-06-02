import SwiftData
import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel = ExercisePickerViewModel()

    let onSelect: (ExerciseCatalog) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading exercises…")
                } else {
                    pickerList
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search exercises")
            .navigationTitle("Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                filterBar
            }
        }
        .background(screenBackground.ignoresSafeArea())
        .task {
            viewModel.load(context: modelContext)
        }
    }

    @ViewBuilder
    private var pickerList: some View {
        List {
            if !viewModel.recentRows.isEmpty, viewModel.trimmedSearchForDisplay.isEmpty {
                Section("Recent") {
                    exerciseRows(viewModel.recentRows)
                }
            }

            if !viewModel.commonRows.isEmpty {
                Section("Common") {
                    exerciseRows(viewModel.commonRows)
                }
            }

            if !viewModel.showSearchAllSection {
                Section {
                    Button("Browse all exercises") {
                        viewModel.browseAllExercises = true
                    }
                }
            }

            if viewModel.showSearchAllSection {
                Section(viewModel.trimmedSearchForDisplay.isEmpty ? "All exercises" : "Search results") {
                    if viewModel.searchAllRows.isEmpty {
                        ContentUnavailableView.search(text: viewModel.searchText)
                    } else {
                        exerciseRows(viewModel.searchAllRows)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func exerciseRows(_ rows: [ExercisePickerRow]) -> some View {
        ForEach(rows) { row in
                        Button {
                            guard let entry = viewModel.catalogEntry(for: row.id) else { return }
                            onSelect(entry)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ExerciseIllustrationView(
                                    catalogEntry: viewModel.catalogEntry(for: row.id),
                                    title: row.name,
                                    compact: true
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name)
                                        .foregroundStyle(.primary)
                                    Text(row.equipment.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
        }
    }

    @ViewBuilder
    private var filterBar: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All muscles", selected: viewModel.muscleFilter == nil) {
                        viewModel.muscleFilter = nil
                    }
                    ForEach(Muscle.allCases.filter { $0 != .fullBody }, id: \.self) { muscle in
                        filterChip(muscleChipLabel(muscle), selected: viewModel.muscleFilter == muscle) {
                            viewModel.muscleFilter = viewModel.muscleFilter == muscle ? nil : muscle
                        }
                    }
                }
                .padding(.horizontal)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All equipment", selected: viewModel.equipmentFilter == nil) {
                        viewModel.equipmentFilter = nil
                    }
                    ForEach(ExerciseEquipment.allCases, id: \.self) { equipment in
                        filterChip(
                            equipment.rawValue.capitalized,
                            selected: viewModel.equipmentFilter == equipment
                        ) {
                            viewModel.equipmentFilter = viewModel.equipmentFilter == equipment ? nil : equipment
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(screenBackground.opacity(0.95))
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? Color("Primary").opacity(0.25) : Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func muscleChipLabel(_ muscle: Muscle) -> String {
        switch muscle {
        case .upperBack: "Upper back"
        case .lowerBack: "Lower back"
        case .frontDelts: "Front delts"
        case .sideDelts: "Side delts"
        case .rearDelts: "Rear delts"
        default: muscle.rawValue.capitalized
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }
}

private extension ExercisePickerViewModel {
    var trimmedSearchForDisplay: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
