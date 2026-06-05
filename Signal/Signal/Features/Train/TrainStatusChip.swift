import SwiftUI

enum TrainStatusChipStyle {
    case warning
    case positive
    case secondary
    case destructive
}

struct TrainStatusChip: View {
    let title: String
    var style: TrainStatusChipStyle = .warning
    var accessibilityIdentifier: String?

    private var foreground: Color {
        switch style {
        case .warning: Color("Warning")
        case .positive: Color("Positive")
        case .secondary: Color("TextSecondary")
        case .destructive: .red
        }
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(foreground.opacity(style == .secondary ? 0.1 : 0.15))
            .clipShape(Capsule())
            .trainAccessibilityIdentifier(accessibilityIdentifier)
    }
}
