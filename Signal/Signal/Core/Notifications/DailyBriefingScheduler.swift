import Foundation
import os
import SwiftData
import UserNotifications

enum SignalNotificationCategory {
    static let dailyBriefing = "daily_briefing"
}

@MainActor
final class DailyBriefingScheduler {
    static let shared = DailyBriefingScheduler()

    private let center = UNUserNotificationCenter.current()
    private let requestIdentifier = "signal.dailyBriefing"

    private init() {}

    static func registerCategories() {
        let category = UNNotificationCategory(
            identifier: SignalNotificationCategory.dailyBriefing,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        Log.notifications.info("registered daily_briefing notification category")
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                Log.notifications.info("notification authorization granted=\(granted, privacy: .public)")
                return granted
            } catch {
                Log.notifications.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        @unknown default:
            return false
        }
    }

    func refreshSchedule(in context: ModelContext) async {
        let preferences = NotificationPreferences.shared
        await center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])

        guard preferences.dailyBriefingEnabled else {
            Log.notifications.info("daily briefing disabled; cleared pending request")
            return
        }

        guard await requestAuthorizationIfNeeded() else {
            Log.notifications.info("daily briefing not scheduled; authorization unavailable")
            return
        }

        let score = RecoveryScoreCalculator.compute(
            metrics: fetchMetricSnapshots(in: context),
            referenceDay: Calendar.current.startOfDay(for: Date()),
            calendar: Calendar.current
        )
        let flags = ReadinessFlagEvaluator.evaluate(
            ReadinessFlagInput(
                metrics: fetchMetricSnapshots(in: context),
                recoveryScore: score,
                referenceDay: Calendar.current.startOfDay(for: Date()),
                calendar: Calendar.current
            )
        )
        let insightLine = fetchPriorityInsightLine(in: context)
        let content = DailyBriefingComposer.compose(
            recoveryScore: score,
            insight: insightLine,
            flags: flags
        )

        var dateComponents = preferences.briefingDateComponents
        dateComponents.calendar = Calendar.current

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = content.title
        notificationContent.body = content.body
        notificationContent.categoryIdentifier = SignalNotificationCategory.dailyBriefing
        notificationContent.sound = .default

        let request = UNNotificationRequest(
            identifier: requestIdentifier,
            content: notificationContent,
            trigger: trigger
        )

        do {
            try await center.add(request)
            Log.notifications.info(
                "scheduled daily briefing hour=\(preferences.briefingHour, privacy: .public) minute=\(preferences.briefingMinute, privacy: .public)"
            )
        } catch {
            Log.notifications.error(
                "failed to schedule daily briefing: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func fetchMetricSnapshots(in context: ModelContext) -> [DailyMetricSnapshot] {
        let descriptor = FetchDescriptor<DailyMetric>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows.map { DailyMetricSnapshot(metric: $0) }
    }

    private func fetchPriorityInsightLine(in context: ModelContext) -> DailyBriefingInsightLine? {
        let descriptor = FetchDescriptor<Insight>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        let now = Date()
        let active = rows.filter { insight in
            guard !insight.isActioned else { return false }
            guard insight.severity == .alert || insight.severity == .warning else { return false }
            guard let expires = insight.expiresAt else { return true }
            return expires > now
        }
        let lines = active.map {
            DailyBriefingInsightLine(bodyText: $0.bodyText, severity: $0.severity)
        }
        return DailyBriefingComposer.selectPriorityInsight(from: lines)
    }
}
