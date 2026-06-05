import SwiftUI

struct LiveHeartRateDecor: View {
    var accent: Color = .red

    private struct Glyph {
        let symbol: String
        let size: CGFloat
        let opacity: Double
        let x: CGFloat
        let y: CGFloat
        let rotation: Double
    }

    private static let glyphs: [Glyph] = [
        Glyph(symbol: "waveform.path.ecg", size: 20, opacity: 0.16, x: -28, y: -12, rotation: 0),
        Glyph(symbol: "waveform.path.ecg", size: 12, opacity: 0.11, x: 30, y: -14, rotation: 6),
        Glyph(symbol: "waveform", size: 10, opacity: 0.09, x: 24, y: 14, rotation: 0),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(Self.glyphs.enumerated()), id: \.offset) { _, glyph in
                Image(systemName: glyph.symbol)
                    .font(.system(size: glyph.size, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent.opacity(glyph.opacity))
                    .offset(x: glyph.x, y: glyph.y)
                    .rotationEffect(.degrees(glyph.rotation))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum LiveHeartRateIcon {
    static let liveSymbol = "waveform.path.ecg"
}
