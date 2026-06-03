import Foundation
import SwiftData
import os

actor ReflectionEngine {
    static let shared = ReflectionEngine()

    private var observationTask: Task<Void, Never>?
    private let calendar: Calendar

    private init() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        calendar = cal
        observationTask = Task { [weak self] in
            await self?.observeTriggers()
        }
    }

    func runReflection(in context: ModelContext, referenceDate: Date? = nil) async {
        let specCount = await MainActor.run { () -> Int in
            let ref = referenceDate ?? Date()
            let snapshot = ReflectionSnapshotBuilder.build(in: context, calendar: calendar, referenceDate: ref)
            let specs = ReflectionRules.evaluate(snapshot: snapshot, calendar: calendar)
            apply(specs: specs, snapshot: snapshot, in: context)
            ReflectionSchedule.markReflectionCompleted()
            Log.recovery.info("reflection finished specs=\(specs.count, privacy: .public)")
            return specs.count
        }
        _ = specCount
    }

    @MainActor
    private func apply(specs: [InsightSpec], snapshot: ReflectionSnapshot, in context: ModelContext) {
        let now = snapshot.referenceDate
        let activeKeys = Set(specs.map(\.dedupeKey))
        expireStaleConditionalInsights(activeKeys: activeKeys, now: now, in: context)
        for spec in specs {
            upsert(spec: spec, now: now, in: context)
        }
        try? context.save()
    }

    @MainActor
    private func upsert(spec: InsightSpec, now: Date, in context: ModelContext) {
        if let existing = fetchInsight(dedupeKey: spec.dedupeKey, in: context) {
            if isActive(existing, now: now) {
                return
            }
            reactivate(existing: existing, spec: spec, now: now)
            return
        }
        context.insert(
            Insight(
                dedupeKey: spec.dedupeKey,
                type: spec.type,
                severity: spec.severity,
                bodyText: spec.bodyText,
                relatedEntity: spec.relatedEntity,
                createdAt: now,
                expiresAt: spec.expiresAt,
                isActioned: false
            )
        )
    }

    @MainActor
    private func reactivate(existing: Insight, spec: InsightSpec, now: Date) {
        existing.type = spec.type
        existing.severity = spec.severity
        existing.bodyText = spec.bodyText
        existing.relatedEntity = spec.relatedEntity
        existing.createdAt = now
        existing.expiresAt = spec.expiresAt
        existing.isActioned = false
    }

    @MainActor
    private func fetchInsight(dedupeKey: String, in context: ModelContext) -> Insight? {
        var descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.dedupeKey == dedupeKey }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @MainActor
    private func isActive(_ insight: Insight, now: Date) -> Bool {
        guard !insight.isActioned else { return false }
        guard let expires = insight.expiresAt else { return true }
        return expires > now
    }

    @MainActor
    private func expireStaleConditionalInsights(activeKeys: Set<String>, now: Date, in context: ModelContext) {
        let managedTypes = Set(InsightType.conditionalTypes.map(\.rawValue))
        let descriptor = FetchDescriptor<Insight>()
        let rows = (try? context.fetch(descriptor)) ?? []
        for insight in rows {
            guard managedTypes.contains(insight.typeRaw) else { continue }
            guard !insight.isActioned else { continue }
            if let expires = insight.expiresAt, expires <= now { continue }
            guard !activeKeys.contains(insight.dedupeKey) else { continue }
            insight.expiresAt = now
        }
    }

    private func observeTriggers() async {
        let workoutFinish = NotificationCenter.default.notifications(
            named: Notification.Name("workoutDidFinish"),
            object: nil
        )
        let deltaFinish = NotificationCenter.default.notifications(
            named: Notification.Name("healthKitProcessDeltaDidFinish"),
            object: nil
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await notification in workoutFinish {
                    guard let container = notification.userInfo?["modelContainer"] as? ModelContainer else {
                        continue
                    }
                    await self.runReflection(in: ModelContext(container))
                }
            }
            group.addTask {
                for await notification in deltaFinish {
                    guard let container = notification.userInfo?["modelContainer"] as? ModelContainer else {
                        continue
                    }
                    await self.runReflection(in: ModelContext(container))
                }
            }
        }
    }
}

extension InsightType {
    static let conditionalTypes: [InsightType] = [
        .volumeBelowMEV,
        .volumeAboveMRV,
        .acwrOverreach,
        .acwrUnderloading,
        .e1RMPlateau,
        .hrvSuppressed,
        .sleepDeficit,
        .proteinGap,
    ]
}
