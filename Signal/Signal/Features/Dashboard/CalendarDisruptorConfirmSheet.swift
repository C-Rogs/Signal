import SwiftData
import SwiftUI

struct CalendarDisruptorConfirmSheet: View {
    let candidate: CalendarDisruptorCandidate
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Tag last night?")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))

            Text("Calendar: \(candidate.eventTitle) last night. Tag as drinking?")
                .font(.body)
                .foregroundStyle(Color("TextSecondary"))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Not drinking") {
                    onDismiss()
                }
                .buttonStyle(.bordered)

                Button("Tag as drinking") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Primary"))
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
