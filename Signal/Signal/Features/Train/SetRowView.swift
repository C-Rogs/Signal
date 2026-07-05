import SwiftData
import SwiftUI
import UIKit

struct SetRowView: View {
    let set: SetEntry
    let mode: ExerciseLoggingMode
    let formatter: DisplayUnitFormatter
    let previousHint: String?
    let onFillPrevious: (() -> Void)?
    let onActivate: () -> Void
    let onCommit: (SetFieldCommit) -> Void
    let onToggleComplete: (Bool) -> Void
    let onDelete: () -> Void

    @State private var setType: WorkoutSetType
    @State private var weightText: String
    @State private var repsText: String
    @State private var distanceText: String
    @State private var durationText: String
    @State private var loggedRPE: Double?
    @State private var showRPESheet = false
    @State private var sheetRPE: Double = WorkoutRPEScale.defaultValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(TrainSetFieldFocusCoordinator.self) private var focusCoordinator
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
        onActivate: @escaping () -> Void = {},
        onCommit: @escaping (SetFieldCommit) -> Void,
        onToggleComplete: @escaping (Bool) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.set = set
        self.mode = mode
        self.formatter = formatter
        self.previousHint = previousHint
        self.onFillPrevious = onFillPrevious
        self.onActivate = onActivate
        self.onCommit = onCommit
        self.onToggleComplete = onToggleComplete
        self.onDelete = onDelete
        _setType = State(initialValue: WorkoutSetType(storageValue: set.setType) ?? .normal)
        _weightText = State(initialValue: formatter.displayMassInputKg(set.weightKg))
        _repsText = State(initialValue: set.reps.map(String.init) ?? "")
        _distanceText = State(initialValue: formatter.displayDistanceInputKm(set.distanceKm))
        _durationText = State(initialValue: Self.formatDurationInput(set.durationSeconds))
        _loggedRPE = State(initialValue: set.rpe)
        _sheetRPE = State(
            initialValue: set.rpe.map { WorkoutRPEScale.snapToPicker($0) } ?? WorkoutRPEScale.defaultValue
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            setColumn
            previousColumn
            if mode == .strength {
                strengthFields
            } else {
                cardioFields
            }
            rpePill
            completeButton
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(set.hasBeenEdited || set.isCompleted ? 1 : 0.92)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showRPESheet) {
            LogSetRPEView(
                setSummary: setSummaryLine,
                selectedRPE: $sheetRPE,
                onDone: {
                    loggedRPE = sheetRPE
                    commitFields()
                    markCompleteIfNeeded()
                }
            )
        }
        .onChange(of: set.persistentModelID) { _, _ in
            syncFromModel()
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if newValue != nil, oldValue == nil {
                onActivate()
            }
            if oldValue != nil, newValue == nil {
                if focusCoordinator.consumeSuppressNextCommit() {
                    TrainWorkoutDiagnostics.record("setRow skipCommit overlayDismiss set=\(set.setIndex)")
                } else {
                    commitFields()
                }
            }
            focusCoordinator.noteEditingActive(newValue != nil)
        }
        .onChange(of: focusCoordinator.dismissGeneration) { _, _ in
            if !focusCoordinator.consumeSuppressNextCommit() {
                commitFields()
            }
            focusedField = nil
            focusCoordinator.noteEditingActive(false)
        }
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
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
                            TrainFeedback.shared.play(.selection)
                        }
                    }
                } label: {
                    Text("W")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.orange)
                        .frame(width: 32, height: 32)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .accessibilityLabel("Warmup set, change type")
            } else {
                Menu {
                    ForEach(WorkoutSetType.allCases) { type in
                        Button(type.label) {
                            setType = type
                            commitFields()
                            TrainFeedback.shared.play(.selection)
                        }
                    }
                } label: {
                    Text("\(set.setIndex + 1)")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(Color("TextPrimary"))
                }
                .accessibilityLabel("Set \(set.setIndex + 1), type \(setType.label)")
            }
        }
        .frame(width: 32)
    }

    @ViewBuilder
    private var previousColumn: some View {
        Group {
            if let previousHint, let onFillPrevious {
                Button {
                    TrainFeedback.shared.play(.fillPrevious)
                    onFillPrevious()
                } label: {
                    Text(previousHint)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color("Primary").opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
        .frame(minWidth: 56)
    }

    @ViewBuilder
    private var strengthFields: some View {
        TextField("0", text: $weightText)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.body.monospacedDigit().weight(.medium))
            .frame(width: 52)
            .focused($focusedField, equals: .weight)
            .accessibilityIdentifier("setWeight-\(set.setIndex)")
            .onSubmit { commitFields() }
        TextField("0", text: $repsText)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .font(.body.monospacedDigit().weight(.medium))
            .frame(width: 40)
            .focused($focusedField, equals: .reps)
            .accessibilityIdentifier("setReps-\(set.setIndex)")
            .onSubmit { commitFields() }
    }

    @ViewBuilder
    private var cardioFields: some View {
        TextField("0", text: $distanceText)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.subheadline.monospacedDigit())
            .frame(width: 44)
            .focused($focusedField, equals: .distance)
            .accessibilityIdentifier("setDistance-\(set.setIndex)")
            .onSubmit { commitFields() }
        TextField("Min", text: $durationText)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .font(.subheadline.monospacedDigit())
            .frame(width: 36)
            .focused($focusedField, equals: .duration)
            .accessibilityIdentifier("setDuration-\(set.setIndex)")
            .onSubmit { commitFields() }
    }

    private var rpePill: some View {
        Button {
            sheetRPE = loggedRPE.map { WorkoutRPEScale.snapToPicker($0) } ?? WorkoutRPEScale.defaultValue
            showRPESheet = true
        } label: {
            Group {
                if let loggedRPE {
                    Text(WorkoutRPEScale.compactLabel(for: loggedRPE))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color("TextPrimary"))
                } else {
                    Text("RPE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color("TextSecondary"))
                }
            }
            .frame(minWidth: 44, minHeight: 32)
            .padding(.horizontal, 8)
            .background(pillBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(width: 48, height: 44)
        .accessibilityIdentifier("setRPE-\(set.setIndex)")
        .accessibilityLabel(loggedRPE.map { "RPE \(WorkoutRPEScale.compactLabel(for: $0)), tap to edit" } ?? "Log RPE")
    }

    private var pillBackground: Color {
        if colorScheme == .dark {
            return Color.white.opacity(loggedRPE == nil ? 0.1 : 0.16)
        }
        return Color("TextSecondary").opacity(loggedRPE == nil ? 0.1 : 0.14)
    }

    private func markCompleteIfNeeded() {
        guard !set.isCompleted else { return }
        onToggleComplete(true)
    }

    private var completeButton: some View {
        Button {
            commitFields()
            TrainFeedback.shared.play(.primaryTap)
            onToggleComplete(!set.isCompleted)
        } label: {
            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(set.isCompleted ? Color("Positive") : Color("TextSecondary"))
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityIdentifier("setComplete-\(set.setIndex)")
        .accessibilityLabel(set.isCompleted ? "Set complete, tap to uncomplete" : "Mark set complete")
    }

    private var rowBackground: Color {
        guard set.isCompleted else { return .clear }
        let tint = Color("Positive")
        if colorScheme == .dark {
            return tint.opacity(0.14)
        }
        return tint.opacity(0.1)
    }

    private var setSummaryLine: String {
        let setNumber = set.setIndex + 1
        switch mode {
        case .strength:
            let weight = strengthWeightLabel
            let reps = repsText.trimmingCharacters(in: .whitespacesAndNewlines)
            let repsLabel = reps.isEmpty ? "—" : reps
            return "Set \(setNumber): \(weight) x \(repsLabel) reps"
        case .cardio:
            let distance = distanceText.trimmingCharacters(in: .whitespacesAndNewlines)
            let duration = durationText.trimmingCharacters(in: .whitespacesAndNewlines)
            let distanceLabel = distance.isEmpty ? "—" : distance
            let durationLabel = duration.isEmpty ? "—" : "\(duration) min"
            return "Set \(setNumber): \(distanceLabel) \(formatter.distanceUnit == .kilometers ? "km" : "mi"), \(durationLabel)"
        }
    }

    private var strengthWeightLabel: String {
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let unit = formatter.massUnit == .kilograms ? "kg" : "lb"
            return "\(trimmed)\(unit)"
        }
        if let kg = set.weightKg {
            return formatter.formatMassKg(kg).replacingOccurrences(of: " ", with: "")
        }
        return "—"
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
                rpe: loggedRPE
            )
        )
    }

    private func syncFromModel() {
        setType = WorkoutSetType(storageValue: set.setType) ?? .normal
        weightText = formatter.displayMassInputKg(set.weightKg)
        repsText = set.reps.map(String.init) ?? ""
        loggedRPE = set.rpe
        sheetRPE = set.rpe.map { WorkoutRPEScale.snapToPicker($0) } ?? WorkoutRPEScale.defaultValue
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
