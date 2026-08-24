import SwiftUI

struct SetValueEditorSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    let title: String
    let placeholder: String
    let allowsDecimal: Bool
    let fieldLabel: String
    let onSave: (String) -> Void

    @State private var text: String

    init(
        title: String,
        placeholder: String,
        initialText: String,
        allowsDecimal: Bool,
        fieldLabel: String,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.allowsDecimal = allowsDecimal
        self.fieldLabel = fieldLabel
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TrainNumpadView(
                    text: $text,
                    allowsDecimal: allowsDecimal,
                    placeholder: placeholder
                )

                Button {
                    onSave(text)
                    TrainWorkoutDiagnostics.record("setValueEditor done field=\(fieldLabel)")
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
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(sheetBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .background else { return }
                dismiss()
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var sheetBackground: Color {
        TrainChrome.screenBackground(colorScheme: colorScheme)
    }
}
