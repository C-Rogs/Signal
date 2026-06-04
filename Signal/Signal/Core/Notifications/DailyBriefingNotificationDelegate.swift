import Foundation
import SwiftData
import UserNotifications

@MainActor
final class DailyBriefingNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if isDailyBriefing(notification.request) {
            await rescheduleAfterDelivery()
        }
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if isDailyBriefing(response.notification.request) {
            await rescheduleAfterDelivery()
        }
    }

    private func isDailyBriefing(_ request: UNNotificationRequest) -> Bool {
        request.identifier == DailyBriefingScheduler.requestIdentifier
    }

    private func rescheduleAfterDelivery() async {
        let context = ModelContext(modelContainer)
        await DailyBriefingScheduler.shared.refreshSchedule(in: context)
    }
}
