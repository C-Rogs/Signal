import Foundation
import SwiftUI

struct RecoveryWidgetSnapshot: Equatable, Sendable {
    let scoreText: String
    let hrvLabel: String
    let colorToken: String
    let scoreValue: Double?
    let gaugeProgress: Double

    var gaugeTintColor: Color {
        Self.gaugeTintColor(for: scoreValue)
    }

    static func gaugeTintColor(for score: Double?) -> Color {
        guard let score else { return Color.secondary }
        if score >= 70 { return .green }
        if score >= 40 { return .orange }
        return .red
    }

    static let waiting = RecoveryWidgetSnapshot(
        scoreText: "—",
        hrvLabel: "Waiting",
        colorToken: "TextSecondary",
        scoreValue: nil,
        gaugeProgress: 0
    )

    static func make(from payload: WatchPayload?) -> RecoveryWidgetSnapshot {
        guard let payload else { return .waiting }
        let score = payload.recoveryScore
        let progress = min(max(score / 100, 0), 1)
        return RecoveryWidgetSnapshot(
            scoreText: "\(payload.scoreInt)",
            hrvLabel: payload.hrvBandDisplayLabel,
            colorToken: payload.scoreColor,
            scoreValue: score,
            gaugeProgress: progress
        )
    }
}
