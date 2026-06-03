import SwiftUI

struct DashboardInsightBanner: View {
    let insight: Insight
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: insight.severity == .alert ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(insight.severity == .alert ? Color("Negative") : Color("Warning"))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Insight")
                        .font(.caption)
                        .foregroundStyle(Color("TextSecondary"))
                    Text(insight.bodyText)
                        .font(.cardLabel)
                        .foregroundStyle(Color("TextPrimary"))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color("TextSecondary"))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("Surface"))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboardInsightBanner")
    }
}
