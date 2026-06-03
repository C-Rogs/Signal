import Foundation

/// Single source of truth for App Store bundle IDs and the shared App Group.
/// Bundle IDs use capital **S** (`Signal`) to match Xcode signing.
/// The App Group uses lowercase **signal**; that is intentional and does not need to match bundle ID casing.
enum SignalIdentifiers: Sendable {
    nonisolated static let iosApp = "com.cameronro.Signal"
    nonisolated static let iosWidgetExtension = "com.cameronro.Signal.SignalWidget"
    nonisolated static let watchApp = "com.cameronro.Signal.watchkitapp"
    nonisolated static let watchWidgetExtension = "com.cameronro.Signal.watchkitapp.SignalWatch-Widget-Extension"
    nonisolated static let appGroup = "group.com.cameronro.signal"

    /// UserDefaults key prefix only (lowercase). Not used for code signing.
    nonisolated static let persistenceKeyPrefix = "com.cameronro.signal"
}
