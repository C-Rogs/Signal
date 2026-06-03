import SwiftUI

struct HRVBandIndicator: View {
    let analysis: HRVAnalysis
    let chartRange: ClosedRange<Double>

    private var displayRange: ClosedRange<Double> {
        let span = max(chartRange.upperBound - chartRange.lowerBound, 1)
        let padding = span * 0.08
        let lower = min(chartRange.lowerBound, analysis.lowerBand) - padding
        let upper = max(chartRange.upperBound, analysis.upperBand) + padding
        return lower...upper
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color("TextSecondary").opacity(0.2))
                    .frame(height: 4)

                Capsule()
                    .fill(Color("Primary").opacity(0.35))
                    .frame(
                        width: bandWidth(totalWidth: width),
                        height: 4
                    )
                    .offset(x: bandOffset(totalWidth: width))

                Circle()
                    .fill(acuteColor)
                    .frame(width: 8, height: 8)
                    .offset(x: position(for: analysis.acuteMean, totalWidth: width) - 4)
            }
        }
        .frame(height: 12)
    }

    private var acuteColor: Color {
        switch classifyAcute() {
        case .aboveUpperBand: Color("Positive")
        case .belowLowerBand: Color("Warning")
        case .withinBand, .insufficientData: Color("Primary")
        }
    }

    private func classifyAcute() -> HRVBandClassification {
        if analysis.acuteMean > analysis.upperBand { return .aboveUpperBand }
        if analysis.acuteMean < analysis.lowerBand { return .belowLowerBand }
        return .withinBand
    }

    private func bandOffset(totalWidth: CGFloat) -> CGFloat {
        position(for: analysis.lowerBand, totalWidth: totalWidth)
    }

    private func bandWidth(totalWidth: CGFloat) -> CGFloat {
        max(
            position(for: analysis.upperBand, totalWidth: totalWidth)
                - position(for: analysis.lowerBand, totalWidth: totalWidth),
            2
        )
    }

    private func position(for value: Double, totalWidth: CGFloat) -> CGFloat {
        let range = displayRange
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return totalWidth / 2 }
        let fraction = (value - range.lowerBound) / span
        return CGFloat(min(1, max(0, fraction))) * totalWidth
    }
}
