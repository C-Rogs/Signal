import SwiftUI

enum TrainChrome {
    static let horizontalPadding: CGFloat = 16
    static let cardCornerRadius: CGFloat = 14

    static func screenBackground(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black : Color("Background")
    }
}

struct TrainSurfaceCard: ViewModifier {
    var cornerRadius: CGFloat = TrainChrome.cardCornerRadius

    func body(content: Content) -> some View {
        content
            .background(Color("Surface"))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func trainSurfaceCard(cornerRadius: CGFloat = TrainChrome.cardCornerRadius) -> some View {
        modifier(TrainSurfaceCard(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func trainAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
