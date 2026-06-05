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

    var bodyBatteryPercentText: String {
        guard scoreValue != nil else { return "—" }
        let text = scoreText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "—" else { return "—" }
        return "\(text)%"
    }

    var batterySymbolName: String {
        Self.batterySymbolName(for: scoreValue)
    }

    static func batterySymbolName(for score: Double?) -> String {
        guard let score else { return "battery.0percent" }
        switch score {
        case 85...:
            return "battery.100percent"
        case 65..<85:
            return "battery.75percent"
        case 45..<65:
            return "battery.50percent"
        case 15..<45:
            return "battery.25percent"
        default:
            return "battery.0percent"
        }
    }

    static func gaugeTintColor(for score: Double?, payload: WatchPayload? = nil) -> Color {
        guard let score else { return Color.secondary }
        if let payload, payload.usesPersonalBands, let p25 = payload.personalP25, let p75 = payload.personalP75 {
            if score >= p75 { return .green }
            if score >= p25 { return .orange }
            return .red
        }
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

    static let preview = RecoveryWidgetSnapshot(
        scoreText: "72",
        hrvLabel: "Within Range",
        colorToken: "Positive",
        scoreValue: 72,
        gaugeProgress: 0.72
    )

    static let bodyBatteryPreview = RecoveryWidgetSnapshot(
        scoreText: "72",
        hrvLabel: "72%",
        colorToken: "Positive",
        scoreValue: 72,
        gaugeProgress: 0.72
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
