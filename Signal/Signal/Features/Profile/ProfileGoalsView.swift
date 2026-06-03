import SwiftData
import SwiftUI

struct ProfileGoalsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(UnitPreferences.self) private var unitPreferences
    @Environment(HealthKitManager.self) private var healthKitManager
    @State private var viewModel: ProfileGoalsViewModel?

    var body: some View {
        ZStack {
            screenBackground
                .ignoresSafeArea()

            if let viewModel {
                formContent(viewModel: viewModel)
            } else {
                ProgressView("Loading profile…")
            }
        }
        .navigationTitle("Profile and goals")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            if let viewModel {
                saveBar(viewModel: viewModel)
            }
        }
        .task {
            if viewModel == nil {
                viewModel = ProfileGoalsViewModel(
                    modelContext: modelContext,
                    unitPreferences: unitPreferences,
                    healthKitManager: healthKitManager
                )
            }
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func formContent(viewModel: ProfileGoalsViewModel) -> some View {
        @Bindable var viewModel = viewModel

        List {
            if let banner = viewModel.healthBannerMessage {
                Section {
                    ProfileGoalsBannerView(
                        symbol: "heart.text.square",
                        message: banner,
                        tint: Color("Primary")
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if case .saved(let message) = viewModel.saveState {
                Section {
                    ProfileGoalsBannerView(
                        symbol: "checkmark.circle",
                        message: message,
                        tint: .green
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if case .failed(let message) = viewModel.saveState {
                Section {
                    ProfileGoalsBannerView(
                        symbol: "exclamationmark.triangle",
                        message: message,
                        tint: .orange
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if let hint = viewModel.healthAccessHint {
                Section {
                    ProfileGoalsBannerView(
                        symbol: "info.circle",
                        message: hint,
                        tint: Color("TextSecondary")
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                profileFieldRow(title: "Height") {
                    TextField("Optional", text: $viewModel.heightCmText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("cm")
                        .foregroundStyle(Color("TextSecondary"))
                }

                profileFieldRow(title: "Body weight") {
                    TextField(massPlaceholder, text: $viewModel.bodyweightDisplayText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }

                Toggle("Use date of birth", isOn: $viewModel.includesDateOfBirth)
                if viewModel.includesDateOfBirth {
                    DatePicker(
                        "Birth date",
                        selection: $viewModel.dateOfBirth,
                        displayedComponents: .date
                    )
                }

                Picker("Sex", selection: $viewModel.biologicalSex) {
                    ForEach(BiologicalSexOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } header: {
                Text("About you")
            } footer: {
                Text(
                    "Apple Health can fill recent body weight (last 30 days), birthday, and sex when access is allowed. Manual entries are optional."
                )
            }

            Section {
                Picker("Primary goal", selection: $viewModel.primaryGoal) {
                    ForEach(GoalType.allCases) { goal in
                        Text(goal.displayName).tag(goal)
                    }
                }
                .onChange(of: viewModel.primaryGoal) { _, _ in
                    viewModel.primaryGoalDidChange()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.primaryGoal.displayName)
                        .font(.cardLabel)
                        .foregroundStyle(Color("TextPrimary"))
                    Text(viewModel.primaryGoal.oneLineDescription)
                        .font(.metadataCaption)
                        .foregroundStyle(Color("TextSecondary"))
                }
                .padding(.vertical, 4)

                Stepper(
                    value: $viewModel.weeklyTrainingDays,
                    in: 1 ... 7
                ) {
                    Text("Training days per week: \(viewModel.weeklyTrainingDays)")
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Target reps in reserve")
                            .foregroundStyle(Color("TextPrimary"))
                        Spacer()
                        Text("\(viewModel.targetRIR)")
                            .font(.cardLabel)
                            .foregroundStyle(Color("Primary"))
                    }
                    HStack(spacing: 8) {
                        Text("Hard")
                            .font(.metadataCaption)
                            .foregroundStyle(Color("TextSecondary"))
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.targetRIR) },
                                set: { viewModel.targetRIR = Int($0.rounded()) }
                            ),
                            in: 0 ... 5,
                            step: 1
                        )
                        .onChange(of: viewModel.targetRIR) { _, _ in
                            viewModel.targetRIRDidChange()
                        }
                        Text("Easy")
                            .font(.metadataCaption)
                            .foregroundStyle(Color("TextSecondary"))
                    }
                    Text("Default for \(viewModel.primaryGoal.displayName): \(viewModel.primaryGoal.defaultRIR) RIR")
                        .font(.metadataCaption)
                        .foregroundStyle(Color("TextSecondary"))
                }

                TextField("Goal notes (optional)", text: $viewModel.goalNotes, axis: .vertical)
                    .lineLimit(2 ... 4)
            } header: {
                Text("Training goal")
            } footer: {
                Text("Warmup suggestions and future coaching use this goal. Cues keep the same tier rules; RIR is stored for upcoming prescription work.")
            }
        }
        .scrollContentBackground(.hidden)
        .disabled(viewModel.isLoading)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private func saveBar(viewModel: ProfileGoalsViewModel) -> some View {
        let isSaving: Bool = {
            if case .saving = viewModel.saveState { return true }
            return false
        }()

        VStack(spacing: 0) {
            Divider()
            Button {
                Task { await viewModel.save() }
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(colorScheme == .dark ? .black : .white)
                    } else {
                        Text(viewModel.saveButtonTitle)
                            .font(.cardLabel)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(colorScheme == .dark ? .black : .white)
            .background(viewModel.canSave ? Color("Primary") : Color("TextSecondary").opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .disabled(!viewModel.canSave)
        }
        .background(screenBackground)
    }

    private func profileFieldRow(
        title: String,
        @ViewBuilder field: () -> some View
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color("TextPrimary"))
            Spacer()
            field()
                .foregroundStyle(Color("TextPrimary"))
        }
    }

    private var massPlaceholder: String {
        let formatter = DisplayUnitFormatter(preferences: unitPreferences)
        switch formatter.massUnit {
        case .kilograms:
            return "kg"
        case .pounds:
            return "lb"
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }
}

private struct ProfileGoalsBannerView: View {
    let symbol: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(message)
                .font(.metadataCaption)
                .foregroundStyle(Color("TextPrimary"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("TextSecondary").opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ProfileGoalsView()
    }
    .environment(UnitPreferences.shared)
    .environment(HealthKitManager(modelContainer: try! SignalModelContainer.make(inMemoryOnly: true)))
    .modelContainer(try! SignalModelContainer.make(inMemoryOnly: true))
}
