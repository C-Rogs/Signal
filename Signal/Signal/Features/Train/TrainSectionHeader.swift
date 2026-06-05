import SwiftUI

struct TrainSectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color("TextPrimary"))
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.metadataCaption)
                        .foregroundStyle(Color("TextSecondary"))
                }
            }
            .padding(.bottom, 8)

            Rectangle()
                .fill(Color("TextSecondary").opacity(0.15))
                .frame(height: 1)
        }
    }
}
