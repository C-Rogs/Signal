import SwiftUI

enum SetHeartRateDisplay {
    static func bpmColor(for avgBPM: Double) -> Color {
        if avgBPM >= 160 {
            return Color("Warning")
        }
        if avgBPM < 120 {
            return Color("Positive")
        }
        return Color("TextSecondary")
    }

    static func workingSetLabel(avgBPM: Double) -> String {
        "♥ \(Int(avgBPM.rounded())) bpm"
    }

    static func restLabel(avgBPM: Double) -> String {
        "Rest: avg \(Int(avgBPM.rounded())) bpm"
    }
}
