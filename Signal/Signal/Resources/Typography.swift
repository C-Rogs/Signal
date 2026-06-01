import SwiftUI

extension Font {
    static var displayLarge: Font {
        .system(.largeTitle, design: .rounded).weight(.bold)
    }

    static var metricValue: Font {
        .system(size: 44, weight: .semibold, design: .rounded)
    }

    static var cardLabel: Font {
        .system(.subheadline, design: .rounded).weight(.medium)
    }

    static var metadataCaption: Font {
        .caption2
    }
}
