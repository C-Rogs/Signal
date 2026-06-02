import SwiftData
import SwiftUI

struct SetRowView: View {
    let set: SetEntry
    let mode: ExerciseLoggingMode
    let formatter: DisplayUnitFormatter
    let onCommit: (SetFieldCommit) -> Void
    let onToggleComplete: (Bool) -> Void
    let onDelete: () -> Void

    @State private var setType: WorkoutSetType
    @State private var weightText: String
    @State private var repsText: String
    @State private var distanceText: String
    @State private var durationText: String
    @State private var rpeText: String
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case weight, reps, distance, duration, rpe
    }

    init(
        set: SetEntry,
        mode: ExerciseLoggingMode,
        formatter: DisplayUnitFormatter,
        onCommit: @escaping (SetFieldCommit) -> Void,
        onToggleComplete: @escaping (Bool) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.set = set
        self.mode = mode
        self.formatter = formatter
        self.onCommit = onCommit
        self.onToggleComplete = onToggleComplete
        self.onDelete = onDelete
        _setType = State(initialValue: WorkoutSetType(storageValue: set.setType) ?? .normal)
        _weightText = State(initialValue: formatter.displayMassInputKg(set.weightKg))
        _repsText = State(initialValue: set.reps.map(String.init) ?? "")
        _distanceText = State(initialValue: formatter.displayDistanceInputKm(set.distanceKm))
        _durationText = State(initialValue: Self.formatDurationInput(set.durationSeconds))
        _rpeText = State(initialValue: set.rpe.map { String(format: "%.1f", $0) } ?? "")
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(set.setIndex + 1)")
                .font(.caption.monospacedDigit())
                .frame(width: 20, alignment: .trailing)
                .foregroundStyle(.secondary)

            Picker("Type", selection: $setType) {
                ForEach(WorkoutSetType.allCases) { type in
                    Text(type.label).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 88)
            .onChange(of: setType) { _, _ in
                commitFields()
            }

            if mode == .strength {
                strengthFields
            } else {
                cardioFields
            }

            rpeField

            Button {
                commitFields()
                onToggleComplete(!set.isCompleted)
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(set.isCompleted ? Color("Primary") : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("setComplete-\(set.setIndex)")
        }
        .padding(.vertical, 4)
        .opacity(set.hasBeenEdited || set.isCompleted ? 1 : 0.92)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .onChange(of: set.persistentModelID) { _, _ in
            syncFromModel()
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue != nil, newValue == nil {
                commitFields()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                commitFields()
            }
        }
    }

    @ViewBuilder
    private var strengthFields: some View {
        TextField("Wt", text: $weightText)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 56)
            .focused($focusedField, equals: .weight)
            .accessibilityIdentifier("setWeight-\(set.setIndex)")
            .onSubmit { commitFields() }
        Text(formatter.massUnit == .kilograms ? "kg" : "lb")
            .font(.caption2)
            .foregroundStyle(.secondary)

        TextField("Reps", text: $repsText)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 44)
            .focused($focusedField, equals: .reps)
            .accessibilityIdentifier("setReps-\(set.setIndex)")
            .onSubmit { commitFields() }
    }

    @ViewBuilder
    private var cardioFields: some View {
        TextField("Dist", text: $distanceText)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 52)
            .focused($focusedField, equals: .distance)
            .accessibilityIdentifier("setDistance-\(set.setIndex)")
            .onSubmit { commitFields() }
        Text(formatter.distanceUnit == .kilometers ? "km" : "mi")
            .font(.caption2)
            .foregroundStyle(.secondary)

        TextField("Min", text: $durationText)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 44)
            .focused($focusedField, equals: .duration)
            .accessibilityIdentifier("setDuration-\(set.setIndex)")
            .onSubmit { commitFields() }
    }

    @ViewBuilder
    private var rpeField: some View {
        TextField("RPE", text: $rpeText)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 40)
            .focused($focusedField, equals: .rpe)
            .accessibilityIdentifier("setRPE-\(set.setIndex)")
            .onSubmit { commitFields() }
    }

    private func commitFields() {
        let weightKg: Double?
        if weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            weightKg = nil
        } else {
            weightKg = formatter.parseMassInputToKg(from: weightText)
        }

        let reps = Int(repsText.trimmingCharacters(in: .whitespacesAndNewlines))
        let distanceKm = distanceText.isEmpty ? nil : formatter.parseDistanceInputToKm(from: distanceText)
        let durationSeconds = Self.parseDurationInput(durationText)
        let rpe = Double(rpeText.replacingOccurrences(of: ",", with: "."))

        onCommit(
            SetFieldCommit(
                setType: setType.storageValue,
                weightKg: weightKg,
                reps: reps,
                distanceKm: distanceKm,
                durationSeconds: durationSeconds,
                rpe: rpe
            )
        )
    }

    private func syncFromModel() {
        setType = WorkoutSetType(storageValue: set.setType) ?? .normal
        weightText = formatter.displayMassInputKg(set.weightKg)
        repsText = set.reps.map(String.init) ?? ""
        distanceText = formatter.displayDistanceInputKm(set.distanceKm)
        durationText = Self.formatDurationInput(set.durationSeconds)
        rpeText = set.rpe.map { String(format: "%.1f", $0) } ?? ""
    }

    static func formatDurationInput(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let minutes = seconds / 60
        return String(minutes)
    }

    static func parseDurationInput(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = Int(trimmed), minutes >= 0 else { return nil }
        return minutes * 60
    }
}
