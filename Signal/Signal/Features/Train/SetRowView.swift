import SwiftData
import SwiftUI

struct SetRowView: View {
    let set: SetEntry
    let mode: ExerciseLoggingMode
    let formatter: DisplayUnitFormatter
    let previousHint: String?
    let onFillPrevious: (() -> Void)?
    let onCommit: (SetFieldCommit) -> Void
    let onToggleComplete: (Bool) -> Void
    let onDelete: () -> Void

    @State private var setType: WorkoutSetType
    @State private var weightText: String
    @State private var repsText: String
    @State private var distanceText: String
    @State private var durationText: String
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case weight, reps, distance, duration
    }

    private var isWarmup: Bool {
        setType == .warmup
    }

    init(
        set: SetEntry,
        mode: ExerciseLoggingMode,
        formatter: DisplayUnitFormatter,
        previousHint: String?,
        onFillPrevious: (() -> Void)?,
        onCommit: @escaping (SetFieldCommit) -> Void,
        onToggleComplete: @escaping (Bool) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.set = set
        self.mode = mode
        self.formatter = formatter
        self.previousHint = previousHint
        self.onFillPrevious = onFillPrevious
        self.onCommit = onCommit
        self.onToggleComplete = onToggleComplete
        self.onDelete = onDelete
        _setType = State(initialValue: WorkoutSetType(storageValue: set.setType) ?? .normal)
        _weightText = State(initialValue: formatter.displayMassInputKg(set.weightKg))
        _repsText = State(initialValue: set.reps.map(String.init) ?? "")
        _distanceText = State(initialValue: formatter.displayDistanceInputKm(set.distanceKm))
        _durationText = State(initialValue: Self.formatDurationInput(set.durationSeconds))
    }

    var body: some View {
        HStack(spacing: 8) {
            setColumn
            previousColumn
            if mode == .strength {
                strengthFields
            } else {
                cardioFields
            }
            completeButton
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
    private var setColumn: some View {
        Group {
            if isWarmup {
                Menu {
                    ForEach(WorkoutSetType.allCases) { type in
                        Button(type.label) {
                            setType = type
                            commitFields()
                        }
                    }
                } label: {
                    Text("W")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.orange)
                        .frame(width: 28, height: 28)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .accessibilityLabel("Warmup set, change type")
            } else {
                Menu {
                    ForEach(WorkoutSetType.allCases) { type in
                        Button(type.label) {
                            setType = type
                            commitFields()
                        }
                    }
                } label: {
                    Text("\(set.setIndex + 1)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Color("TextPrimary"))
                }
                .accessibilityLabel("Set \(set.setIndex + 1), type \(setType.label)")
            }
        }
        .frame(width: 28)
    }

    @ViewBuilder
    private var previousColumn: some View {
        Group {
            if let previousHint, let onFillPrevious {
                Button(action: {
                    onFillPrevious()
                }) {
                    Text(previousHint)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color("Primary").opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous \(previousHint), tap to fill")
                .accessibilityIdentifier("setPrevious-\(set.setIndex)")
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(Color("TextSecondary").opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var strengthFields: some View {
        TextField("0", text: $weightText)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 56)
            .focused($focusedField, equals: .weight)
            .accessibilityIdentifier("setWeight-\(set.setIndex)")
            .onSubmit { commitFields() }
        TextField("0", text: $repsText)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 44)
            .focused($focusedField, equals: .reps)
            .accessibilityIdentifier("setReps-\(set.setIndex)")
            .onSubmit { commitFields() }
    }

    @ViewBuilder
    private var cardioFields: some View {
        TextField("0", text: $distanceText)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 52)
            .focused($focusedField, equals: .distance)
            .accessibilityIdentifier("setDistance-\(set.setIndex)")
            .onSubmit { commitFields() }
        TextField("Min", text: $durationText)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 44)
            .focused($focusedField, equals: .duration)
            .accessibilityIdentifier("setDuration-\(set.setIndex)")
            .onSubmit { commitFields() }
    }

    private var completeButton: some View {
        Button {
            commitFields()
            onToggleComplete(!set.isCompleted)
        } label: {
            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(set.isCompleted ? Color("Positive") : Color("TextSecondary"))
        }
        .buttonStyle(.plain)
        .frame(width: 28)
        .accessibilityIdentifier("setComplete-\(set.setIndex)")
    }

    private var rowBackground: Color {
        guard set.isCompleted else { return .clear }
        let tint = Color("Positive")
        if colorScheme == .dark {
            return tint.opacity(0.14)
        }
        return tint.opacity(0.1)
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

        onCommit(
            SetFieldCommit(
                setType: setType.storageValue,
                weightKg: weightKg,
                reps: reps,
                distanceKm: distanceKm,
                durationSeconds: durationSeconds,
                rpe: set.rpe
            )
        )
    }

    private func syncFromModel() {
        setType = WorkoutSetType(storageValue: set.setType) ?? .normal
        weightText = formatter.displayMassInputKg(set.weightKg)
        repsText = set.reps.map(String.init) ?? ""
        distanceText = formatter.displayDistanceInputKm(set.distanceKm)
        durationText = Self.formatDurationInput(set.durationSeconds)
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
