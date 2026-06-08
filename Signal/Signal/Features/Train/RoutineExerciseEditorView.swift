import SwiftData
import SwiftUI

struct RoutineExerciseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(UnitPreferences.self) private var unitPreferences

    @Bindable var slot: RoutineExercise

    private var formatter: DisplayUnitFormatter {
        DisplayUnitFormatter(preferences: unitPreferences)
    }

    private var displayTitle: String {
        slot.catalogEntry?.canonicalName ?? slot.exerciseTitleFallback ?? "Exercise"
    }

    private var sortedSets: [RoutinePresetSet] {
        slot.sortedPresetSets
    }

    var body: some View {
        Form {
            Section {
                Text(displayTitle)
                    .font(.headline)
            }

            Section("Rest") {
                Stepper(
                    "Rest: \(slot.restDurationSeconds)s",
                    value: $slot.restDurationSeconds,
                    in: 0...600,
                    step: 15
                )
                .frame(minHeight: 44)

                Toggle("Auto-start rest on set complete", isOn: $slot.autoStartRestOnSetComplete)
                    .frame(minHeight: 44)
            }

            Section("Sets") {
                if sortedSets.isEmpty {
                    Text("No prescribed sets. Workout will autofill from last session.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(sortedSets, id: \.persistentModelID) { preset in
                    RoutinePresetSetRow(preset: preset, formatter: formatter) {
                        try? modelContext.save()
                    }
                }
                .onDelete(perform: deleteSets)

                Button {
                    addSet()
                } label: {
                    Label("Add Set", systemImage: "plus")
                }
                .frame(minHeight: 44)
            }
        }
        .scrollContentBackground(.hidden)
        .background(screenBackground.ignoresSafeArea())
        .navigationTitle("Edit Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var screenBackground: Color {
        TrainChrome.screenBackground(colorScheme: colorScheme)
    }

    private func addSet() {
        let nextIndex = (sortedSets.map(\.setIndex).max() ?? -1) + 1
        let preset = RoutinePresetSet(
            setIndex: nextIndex,
            setType: WorkoutSetType.normal.storageValue
        )
        preset.routineExercise = slot
        slot.presetSets.append(preset)
        try? modelContext.save()
    }

    private func deleteSets(at offsets: IndexSet) {
        var ordered = sortedSets
        let removed = offsets.map { ordered[$0] }
        ordered.remove(atOffsets: offsets)
        for preset in removed {
            modelContext.delete(preset)
        }
        for (index, preset) in ordered.enumerated() {
            preset.setIndex = index
        }
        try? modelContext.save()
    }
}

private struct RoutinePresetSetRow: View {
    @Bindable var preset: RoutinePresetSet
    let formatter: DisplayUnitFormatter
    let onCommit: () -> Void

    @State private var weightText: String
    @State private var repsText: String
    @State private var setType: WorkoutSetType

    init(preset: RoutinePresetSet, formatter: DisplayUnitFormatter, onCommit: @escaping () -> Void) {
        self.preset = preset
        self.formatter = formatter
        self.onCommit = onCommit
        _weightText = State(initialValue: formatter.displayMassInputKg(preset.weightKg))
        _repsText = State(initialValue: preset.reps.map(String.init) ?? "")
        _setType = State(initialValue: WorkoutSetType(storageValue: preset.setType) ?? .normal)
    }

    private var isWarmup: Bool {
        setType == .warmup
    }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(WorkoutSetType.allCases) { type in
                    Button(type.label) {
                        setType = type
                        preset.setType = type.storageValue
                        onCommit()
                    }
                }
            } label: {
                Group {
                    if isWarmup {
                        Text("W")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.orange)
                    } else {
                        Text("\(preset.setIndex + 1)")
                            .font(.body.monospacedDigit().weight(.semibold))
                    }
                }
                .frame(width: 32, height: 32)
            }
            .frame(minWidth: 44, minHeight: 44)

            TextField(formatter.massUnit == .kilograms ? "kg" : "lb", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 56)
                .onChange(of: weightText) { _, _ in commitWeight() }

            Text("×")
                .foregroundStyle(.secondary)

            TextField("reps", text: $repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 44)
                .onChange(of: repsText) { _, _ in commitReps() }

            if let rpe = preset.rpe {
                Text("@\(formatRPE(rpe))")
                    .font(.caption)
                    .foregroundStyle(Color("TextSecondary"))
            }
        }
        .frame(minHeight: 44)
    }

    private func commitWeight() {
        preset.weightKg = formatter.parseMassInputToKg(from: weightText)
        onCommit()
    }

    private func commitReps() {
        let trimmed = repsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            preset.reps = nil
        } else {
            preset.reps = Int(trimmed)
        }
        onCommit()
    }

    private func formatRPE(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
