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
    static let requestIdentifier = "signal.dailyBriefing"

    private let center = UNUserNotificationCenter.current()

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

    nonisolated static func nextBriefingFireDate(
        from now: Date,
        briefingHour: Int,
        briefingMinute: Int,
        calendar: Calendar
    ) -> Date {
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        dayComponents.hour = briefingHour
        dayComponents.minute = briefingMinute
        dayComponents.second = 0
        dayComponents.calendar = calendar
        guard let todayFire = calendar.date(from: dayComponents) else {
            return now
        }
        if todayFire > now {
            return todayFire
        }
        return calendar.date(byAdding: .day, value: 1, to: todayFire) ?? todayFire
    }

    static func composeBriefingContent(
        in context: ModelContext,
        referenceDay: Date,
        calendar: Calendar = .current
    ) -> DailyBriefingContent {
        let referenceStart = calendar.startOfDay(for: referenceDay)
        let metrics = fetchMetricSnapshots(in: context)
        let score = RecoveryScoreCalculator.compute(
            metrics: metrics,
            referenceDay: referenceStart,
            calendar: calendar
        )
        let flags = ReadinessFlagEvaluator.evaluate(
            ReadinessFlagInput(
                metrics: metrics,
                recoveryScore: score,
                referenceDay: referenceStart,
                calendar: calendar
            )
        )
        let insightLine = fetchPriorityInsightLine(in: context)
        return DailyBriefingComposer.compose(
            recoveryScore: score,
            insight: insightLine,
            flags: flags
        )
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

    func refreshSchedule(in context: ModelContext, now: Date = Date()) async {
        let preferences = NotificationPreferences.shared
        await center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])

        guard preferences.dailyBriefingEnabled else {
            Log.notifications.info("daily briefing disabled; cleared pending request")
            return
        }

        guard await requestAuthorizationIfNeeded() else {
            Log.notifications.info("daily briefing not scheduled; authorization unavailable")
            return
        }

        let calendar = Calendar.current
        let fireDate = Self.nextBriefingFireDate(
            from: now,
            briefingHour: preferences.briefingHour,
            briefingMinute: preferences.briefingMinute,
            calendar: calendar
        )
        let referenceDay = calendar.startOfDay(for: fireDate)
        let content = Self.composeBriefingContent(
            in: context,
            referenceDay: referenceDay,
            calendar: calendar
        )

        let triggerComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = content.title
        notificationContent.body = content.body
        notificationContent.categoryIdentifier = SignalNotificationCategory.dailyBriefing
        notificationContent.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.requestIdentifier,
            content: notificationContent,
            trigger: trigger
        )

        do {
            try await center.add(request)
            Log.notifications.info(
                "scheduled daily briefing fire=\(fireDate, privacy: .public) hour=\(preferences.briefingHour, privacy: .public) minute=\(preferences.briefingMinute, privacy: .public)"
            )
        } catch {
            Log.notifications.error(
                "failed to schedule daily briefing: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func fetchMetricSnapshots(in context: ModelContext) -> [DailyMetricSnapshot] {
        let descriptor = FetchDescriptor<DailyMetric>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows.map { DailyMetricSnapshot(metric: $0) }
    }

    private static func fetchPriorityInsightLine(in context: ModelContext) -> DailyBriefingInsightLine? {
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
