import SwiftUI

struct WarmupSuggestionBannerView: View {
    let summary: String
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary)
                .font(.caption)
                .foregroundStyle(Color("TextSecondary"))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Add warmups", action: onAdd)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Color("Primary"))
                    .accessibilityIdentifier("warmupSuggestionAdd")

                Button("Dismiss", action: onDismiss)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color("TextSecondary"))
                    .accessibilityIdentifier("warmupSuggestionDismiss")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color("Primary").opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color("Primary").opacity(0.2), lineWidth: 1)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("warmupSuggestionBanner")
    }
}
