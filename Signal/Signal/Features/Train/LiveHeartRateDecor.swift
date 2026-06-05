import SwiftUI

/// Low-opacity ECG waveforms behind live BPM (clinical / fitness, not decorative hearts).
struct LiveHeartRateDecor: View {
    var accent: Color = Color("Primary")

    private struct Glyph {
        let symbol: String
        let size: CGFloat
        let opacity: Double
        let x: CGFloat
        let y: CGFloat
        let rotation: Double
    }

    private static let glyphs: [Glyph] = [
        Glyph(symbol: "waveform.path.ecg", size: 30, opacity: 0.14, x: -34, y: -16, rotation: 0),
        Glyph(symbol: "waveform.path.ecg", size: 18, opacity: 0.1, x: 38, y: -20, rotation: 8),
        Glyph(symbol: "waveform", size: 16, opacity: 0.08, x: 36, y: 18, rotation: 0),
        Glyph(symbol: "waveform.path.ecg", size: 12, opacity: 0.07, x: -36, y: 18, rotation: -6),
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
