import SwiftUI

struct DashboardMetricCard: View {
    let title: String
    let valueText: String
    let subtitle: String?
    let symbol: Symbol
    let points: [DashboardChartPoint]
    let valueStyle: DashboardChartValueStyle
    var tint: Color = Color("Primary")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                symbol.hierarchicalImage(tint: tint)
                    .font(.title3)
                Text(title)
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextPrimary"))
                Spacer(minLength: 0)
            }

            Text(valueText)
                .font(.metricValue)
                .foregroundStyle(Color("TextPrimary"))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            if let subtitle {
                Text(subtitle)
                    .font(.metadataCaption)
                    .foregroundStyle(Color("TextSecondary"))
            }

            DashboardSparklineChart(points: points, valueStyle: valueStyle, tint: tint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("Surface"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
