import Foundation
import SwiftData
import Testing
@testable import Signal

struct DerivedMetricsProteinTests {
  @MainActor
  @Test func proteinTargetUsesReferenceDayOnly() async throws {
    let container = try SignalModelContainer.make(inMemoryOnly: true)
    let context = ModelContext(container)

    let profile = UserProfile()
    profile.bodyweightKg = 80
    context.insert(profile)

    let calendar = SchedulingCalendar.make()
    let today = calendar.startOfDay(for: Date())
    let oldDay = try #require(calendar.date(byAdding: .day, value: -30, to: today))

    context.insert(DailyNutrition(date: oldDay, proteinG: 200, source: "test"))
    try context.save()

    await DerivedMetricsService.shared.invalidateCache()
    let withoutToday = await DerivedMetricsService.shared.snapshot(modelContainer: container)
    #expect(withoutToday.proteinTarget == nil)

    context.insert(DailyNutrition(date: today, proteinG: 50, source: "test"))
    try context.save()

    await DerivedMetricsService.shared.invalidateCache()
    let withToday = await DerivedMetricsService.shared.snapshot(modelContainer: container)
    #expect(withToday.proteinTarget?.actualGrams == 50)
  }
}
