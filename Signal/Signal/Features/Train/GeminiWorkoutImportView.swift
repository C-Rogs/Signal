import SwiftData
import SwiftUI

struct GeminiWorkoutImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let onStarted: (PersistentIdentifier) -> Void

    @State private var pasteText = ""
    @State private var parseError: String?
    @State private var previewPlan: ParsedWorkoutPlan?
    @State private var showPreview = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste a workout exported from Gemini or another planner. Signal will parse exercises and sets for preview before you start.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextEditor(text: $pasteText)
                    .font(.body.monospaced())
                    .padding(8)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(minHeight: 220)
                    .accessibilityIdentifier("geminiImportTextEditor")

                if let parseError {
                    Text(parseError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .background(screenBackground.ignoresSafeArea())
            .navigationTitle("Import Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Paste") {
                        if let clipboard = UIPasteboard.general.string {
                            pasteText = clipboard
                            parseError = nil
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Preview") { openPreview() }
                        .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showPreview) {
                if let previewPlan {
                    GeminiWorkoutImportPreviewView(
                        plan: previewPlan,
                        onStarted: { sessionID in
                            showPreview = false
                            dismiss()
                            onStarted(sessionID)
                        },
                        onCancel: {
                            showPreview = false
                        }
                    )
                }
            }
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    private var fieldBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    private func openPreview() {
        parseError = nil
        let plan = GeminiWorkoutPasteParser.parse(pasteText)
        guard !plan.exercises.isEmpty else {
            parseError = "No exercises found. Check the format and try again."
            return
        }
        previewPlan = plan
        showPreview = true
    }
}
