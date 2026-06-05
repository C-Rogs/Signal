import SwiftUI

struct LogSetRPEView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let setSummary: String
    @Binding var selectedRPE: Double
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text(setSummary)
                        .font(.metadataCaption)
                        .foregroundStyle(Color("TextSecondary"))
                        .multilineTextAlignment(.center)

                    Text(WorkoutRPEScale.compactLabel(for: selectedRPE))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color("TextPrimary"))
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.2), value: selectedRPE)

                    Text(WorkoutRPEScale.effortTitle(for: selectedRPE))
                        .font(.headline)
                        .foregroundStyle(Color("TextPrimary"))

                    Text(WorkoutRPEScale.effortDetail(for: selectedRPE))
                        .font(.subheadline)
                        .foregroundStyle(Color("TextSecondary"))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                .padding(.horizontal, 24)

                Spacer(minLength: 20)

                rpePicker
                    .padding(.bottom, 8)

                Button {
                    onDone()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Primary"))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(sheetBackground.ignoresSafeArea())
            .navigationTitle("Log RPE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var sheetBackground: Color {
        TrainChrome.screenBackground(colorScheme: colorScheme)
    }

    private var rpePicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(WorkoutRPEScale.pickerValues, id: \.self) { value in
                        rpePickerItem(value)
                            .id(value)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .onAppear {
                proxy.scrollTo(selectedRPE, anchor: .center)
            }
            .onChange(of: selectedRPE) { _, newValue in
                withAnimation(.snappy(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func rpePickerItem(_ value: Double) -> some View {
        let isSelected = selectedRPE == value
        return Button {
            if selectedRPE != value {
                TrainFeedback.shared.play(.rpeSelect)
            }
            selectedRPE = value
        } label: {
            Text(WorkoutRPEScale.compactLabel(for: value))
                .font(.body.weight(isSelected ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : Color("TextPrimary"))
                .frame(width: 40, height: 40)
                .background {
                    if isSelected {
                        Circle().fill(Color("Primary"))
                    } else {
                        Circle().fill(Color("TextSecondary").opacity(colorScheme == .dark ? 0.12 : 0.08))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("RPE \(WorkoutRPEScale.compactLabel(for: value))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
