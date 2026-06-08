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
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste a workout exported from Gemini or another planner. Signal will parse exercises and sets for preview before you start.")
                    .font(.body)
                    .foregroundStyle(Color("TextSecondary"))
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $pasteText)
                    .font(.body.monospaced())
                    .padding(10)
                    .frame(minHeight: 220)
                    .trainSurfaceCard(cornerRadius: 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color("TextSecondary").opacity(0.15), lineWidth: 1)
                    }
                    .accessibilityIdentifier("geminiImportTextEditor")

                if let parseError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color("Warning"))
                        Text(parseError)
                            .font(.metadataCaption)
                            .foregroundStyle(Color("Warning"))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .trainSurfaceCard(cornerRadius: 12)
                }

                Spacer(minLength: 0)

                Button {
                    openPreview()
                } label: {
                    Text("Preview Workout")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Primary"))
                .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(TrainChrome.horizontalPadding)
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
                    .fontWeight(.medium)
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
                        onRoutineSaved: {
                            showPreview = false
                            dismiss()
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
        TrainChrome.screenBackground(colorScheme: colorScheme)
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
