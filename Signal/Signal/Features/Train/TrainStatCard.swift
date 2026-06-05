import SwiftUI

struct TrainStatCard: View {
    let title: String
    let value: String
    var emphasize: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color("TextSecondary"))
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(emphasize ? Color("Primary") : Color("TextPrimary"))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainSurfaceCard()
    }
}
