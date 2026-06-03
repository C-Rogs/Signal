import SwiftUI

struct DashboardStrainBanner: View {
    let assessment: ReadinessFlagsAssessment

    private var tint: Color {
        switch assessment.aggregateSeverity {
        case .notice: Color("Warning")
        case .caution: Color("Warning")
        case .elevated: Color("Negative")
        }
    }

    private var symbolName: String {
        switch assessment.aggregateSeverity {
        case .notice: "waveform.path.ecg"
        case .caution: "exclamationmark.circle.fill"
        case .elevated: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.title3)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recovery signals")
                        .font(.caption)
                        .foregroundStyle(Color("TextSecondary"))
                    Text(assessment.headline)
                        .font(.cardLabel)
                        .foregroundStyle(Color("TextPrimary"))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(assessment.detail)
                        .font(.metadataCaption)
                        .foregroundStyle(Color("TextSecondary"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("Surface"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("dashboardStrainBanner")
    }
}
