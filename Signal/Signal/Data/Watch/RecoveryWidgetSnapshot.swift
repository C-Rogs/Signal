import Foundation

struct RecoveryWidgetSnapshot: Equatable, Sendable {
    let scoreText: String
    let hrvLabel: String
    let colorToken: String

    static let waiting = RecoveryWidgetSnapshot(
        scoreText: "—",
        hrvLabel: "Waiting",
        colorToken: "TextSecondary"
    )

    static func make(from payload: WatchPayload?) -> RecoveryWidgetSnapshot {
        guard let payload else { return .waiting }
        return RecoveryWidgetSnapshot(
            scoreText: "\(payload.scoreInt)",
            hrvLabel: payload.hrvBandDisplayLabel,
            colorToken: payload.scoreColor
        )
    }
}
