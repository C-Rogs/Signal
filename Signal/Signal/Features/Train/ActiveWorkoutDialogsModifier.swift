import SwiftUI

struct ActiveWorkoutDialogsModifier: ViewModifier {
    @Binding var showDiscardConfirm: Bool
    @Binding var showFinishIncompleteConfirm: Bool
    @Binding var showFinishEmptyConfirm: Bool
    let incompleteExerciseCount: Int
    let onDiscard: () -> Void
    let onFinish: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Discard workout?",
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive, action: onDiscard)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the in-progress session and cannot be undone.")
            }
            .confirmationDialog(
                "Finish with exercises incomplete?",
                isPresented: $showFinishIncompleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Finish anyway", action: onFinish)
                Button("Keep logging", role: .cancel) {}
            } message: {
                Text(incompleteMessage)
            }
            .confirmationDialog(
                "Finish without exercises?",
                isPresented: $showFinishEmptyConfirm,
                titleVisibility: .visible
            ) {
                Button("Finish", action: onFinish)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This workout has no exercises logged.")
            }
    }

    private var incompleteMessage: String {
        let noun = incompleteExerciseCount == 1 ? "exercise" : "exercises"
        return "\(incompleteExerciseCount) \(noun) still not fully logged. Incomplete sections stay highlighted so you can finish strong next time."
    }
}
