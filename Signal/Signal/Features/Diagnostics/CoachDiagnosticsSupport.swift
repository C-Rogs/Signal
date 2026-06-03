import Foundation
import FoundationModels

enum CoachDiagnosticsCopy {
    static let modelNotReadyHelp = """
        Apple Intelligence model is not ready yet. Signal cannot start or monitor that download.

        Retry Ask after Settings shows Apple Intelligence ready, or Writing Tools work in Notes or Mail.

        If Settings shows Downloading but nothing moves for a long time, the download is usually stuck at the OS level:

        1. Storage: Settings → General → iPhone Storage. Free several GB (often 5-15+ GB helps), then wait 30+ minutes on Wi-Fi.
        2. Network: Use Wi-Fi. Briefly turn off VPN, iCloud Private Relay, or Limit IP Address Tracking on Wi-Fi. Try another network if home Wi-Fi blocks large Apple downloads.
        3. Power: Plug in, Low Power Mode off. Leave the phone on the Apple Intelligence settings screen 10-15 minutes (screen may dim; do not force-quit Settings).
        4. Do not flip the Apple Intelligence toggle off and on; that often restarts a stuck download.

        Xcode cannot push or monitor this download. Confirm in Settings → Apple Intelligence & Siri what it shows.
        """
}

enum CoachModelAvailabilityFormatter {
    struct Status: Sendable, Equatable {
        let label: String
        let canAskCoach: Bool
        let helpText: String?
    }

    static func status(for availability: SystemLanguageModel.Availability) -> Status {
        switch availability {
        case .available:
            return Status(label: "Available", canAskCoach: true, helpText: nil)
        case .unavailable(.modelNotReady):
            return Status(
                label: "Downloading or not ready",
                canAskCoach: false,
                helpText: CoachDiagnosticsCopy.modelNotReadyHelp
            )
        case .unavailable(.appleIntelligenceNotEnabled):
            return Status(
                label: "Apple Intelligence off",
                canAskCoach: false,
                helpText: "Turn on Apple Intelligence in Settings → Apple Intelligence & Siri, then retry."
            )
        case .unavailable(.deviceNotEligible):
            return Status(
                label: "Device not eligible",
                canAskCoach: false,
                helpText: "This device does not support Apple Intelligence."
            )
        case .unavailable:
            return Status(
                label: "Unavailable",
                canAskCoach: false,
                helpText: "Foundation Models are unavailable on this device right now."
            )
        }
    }

    static func currentStatus() -> Status {
        status(for: SystemLanguageModel.default.availability)
    }
}

struct CoachContextDiagnostics: Sendable, Equatable {
    let ragDayCount: Int
    let ragCharacterCount: Int
    let insightCount: Int
    let recentWorkoutCount: Int
    let assembledPromptCharacters: Int
    let ragPreview: String
    let fullContextPreview: String

    var summaryLine: String {
        "RAG \(ragDayCount) days (\(ragCharacterCount) chars) · insights \(insightCount) · workouts \(recentWorkoutCount) · prompt \(assembledPromptCharacters) chars"
    }
}
