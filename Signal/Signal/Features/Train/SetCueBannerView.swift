import SwiftUI

struct SetCueBannerView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .multilineTextAlignment(.leading)
            .foregroundStyle(Color("Primary"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 34)
            .padding(.trailing, 8)
            .padding(.bottom, 4)
            .accessibilityIdentifier("setCueBanner")
    }
}
