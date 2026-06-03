import SwiftData
import SwiftUI

struct ProfileGoalsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(UnitPreferences.self) private var unitPreferences
    @State private var viewModel: ProfileGoalsViewModel?

    var body: some View {
        ZStack {
            screenBackground
                .ignoresSafeArea()

            if let viewModel {
                formContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel == nil {
                let model = ProfileGoalsViewModel(
                    modelContext: modelContext,
                    unitPreferences: unitPreferences
                )
                model.load()
                viewModel = model
            } else {
                viewModel?.load()
            }
        }
    }

    @ViewBuilder
    private func formContent(viewModel: ProfileGoalsViewModel) -> some View {
        @Bindable var viewModel = viewModel

        List {
            Section {
                HStack {
                    Text("Height")
                    Spacer()
                    TextField("cm", text: $viewModel.heightCmText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Color("TextPrimary"))
                    Text("cm")
                        .foregroundStyle(Color("TextSecondary"))
                }

                HStack {
                    Text("Current bodyweight")
                    Spacer()
                    TextField(massPlaceholder, text: $viewModel.bodyweightDisplayText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Color("TextPrimary"))
                }

                Toggle("Date of birth", isOn: $viewModel.includesDateOfBirth)
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
                Text("All fields are optional. Bodyweight saves a new log entry each time you save.")
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

                Text(viewModel.primaryGoal.oneLineDescription)
                    .font(.metadataCaption)
                    .foregroundStyle(Color("TextSecondary"))

                Stepper(
                    "Days per week: \(viewModel.weeklyTrainingDays)",
                    value: $viewModel.weeklyTrainingDays,
                    in: 1 ... 7
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Target effort (RIR)")
                        Spacer()
                        Text("\(viewModel.targetRIR)")
                            .foregroundStyle(Color("TextSecondary"))
                    }
                    HStack {
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
                }

                TextField("Notes (optional)", text: $viewModel.goalNotes, axis: .vertical)
                    .lineLimit(2 ... 4)
            } header: {
                Text("Training goal")
            } footer: {
                Text("Reps in reserve: lower means closer to failure. Defaults follow your goal type.")
            }

            Section {
                Button("Save") {
                    viewModel.save()
                }
                .font(.cardLabel)
                .foregroundStyle(Color("Primary"))

                if viewModel.didSaveSuccessfully {
                    Text("Saved.")
                        .font(.metadataCaption)
                        .foregroundStyle(Color("TextSecondary"))
                }
                if let error = viewModel.saveErrorMessage {
                    Text(error)
                        .font(.metadataCaption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var massPlaceholder: String {
        let formatter = DisplayUnitFormatter(preferences: unitPreferences)
        switch formatter.massUnit {
        case .kilograms: return "kg"
        case .pounds: return "lb"
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }
}

#Preview {
    NavigationStack {
        ProfileGoalsView()
    }
    .environment(UnitPreferences.shared)
    .modelContainer(try! SignalModelContainer.make(inMemoryOnly: true))
}
