import SwiftUI

struct WellnessCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let muscles: [Muscle]
    let onSave: (Int, Int, Int, [String: Int], String?) -> Void
    let onSkip: () -> Void

    @State private var energy = 3.0
    @State private var mood = 3.0
    @State private var stress = 3.0
    @State private var notes = ""
    @State private var muscleEffort: [Muscle: Double] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    labeledSlider("Energy", value: $energy)
                    labeledSlider("Mood", value: $mood)
                    labeledSlider("Stress", value: $stress)
                } header: {
                    Text("How do you feel?")
                }

                if !muscles.isEmpty {
                    Section {
                        ForEach(muscles, id: \.self) { muscle in
                            labeledSlider(muscleLabel(muscle), value: binding(for: muscle))
                        }
                    } header: {
                        Text("Muscle effort today")
                    } footer: {
                        Text(
                            "Optional. Rate how hard trained muscles felt during this session. Next-day soreness is different and can be logged later."
                        )
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(screenBackground.ignoresSafeArea())
            .navigationTitle("Wellness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onSkip()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            Int(energy.rounded()),
                            Int(mood.rounded()),
                            Int(stress.rounded()),
                            effortMap(),
                            notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
                        )
                        dismiss()
                    }
                }
            }
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    private func labeledSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded())) · \(FivePointScale.label(for: value.wrappedValue))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .monospacedDigit()
            }
            Slider(value: value, in: 1...5, step: 1)
        }
    }

    private func binding(for muscle: Muscle) -> Binding<Double> {
        Binding(
            get: { muscleEffort[muscle] ?? 1 },
            set: { muscleEffort[muscle] = $0 }
        )
    }

    private func effortMap() -> [String: Int] {
        var map: [String: Int] = [:]
        for (muscle, value) in muscleEffort where value > 1 {
            map[muscle.rawValue] = Int(value.rounded())
        }
        return map
    }

    private func muscleLabel(_ muscle: Muscle) -> String {
        switch muscle {
        case .upperBack: "Upper back"
        case .lowerBack: "Lower back"
        case .frontDelts: "Front delts"
        case .sideDelts: "Side delts"
        case .rearDelts: "Rear delts"
        default:
            muscle.rawValue.capitalized
        }
    }
}

private enum FivePointScale {
    static func label(for value: Double) -> String {
        switch Int(value.rounded()) {
        case 1: "Low"
        case 2: "Below avg"
        case 3: "OK"
        case 4: "Good"
        case 5: "High"
        default: "OK"
        }
    }
}
