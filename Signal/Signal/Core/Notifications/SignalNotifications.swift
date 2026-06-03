import Foundation
import SwiftData

extension Notification.Name {
    static let goalDidChange = Notification.Name("goalDidChange")
    static let workoutDidFinish = Notification.Name("workoutDidFinish")
    static let healthKitProcessDeltaDidFinish = Notification.Name("healthKitProcessDeltaDidFinish")
}
