import Foundation
import SwiftData
import os

enum DailyNutritionStore {
    @MainActor
    static func upsert(_ nutrition: DailyNutrition, in context: ModelContext) throws {
        let day = nutrition.date
        var descriptor = FetchDescriptor<DailyNutrition>(
            predicate: #Predicate { $0.date == day }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.dietaryEnergyKcal = nutrition.dietaryEnergyKcal
            existing.proteinG = nutrition.proteinG
            existing.carbsG = nutrition.carbsG
            existing.fatTotalG = nutrition.fatTotalG
            existing.fatSaturatedG = nutrition.fatSaturatedG
            existing.fiberG = nutrition.fiberG
            existing.sugarG = nutrition.sugarG
            existing.sodiumMg = nutrition.sodiumMg
            existing.source = nutrition.source
        } else {
            context.insert(nutrition)
        }
    }

    @MainActor
    static func upsertBatch(_ items: [DailyNutrition], in context: ModelContext) throws -> Int {
        guard !items.isEmpty else { return 0 }
        for item in items {
            try upsert(item, in: context)
        }
        try context.save()
        return items.count
    }

    @MainActor
    static func fetch(for day: Date, in context: ModelContext) throws -> DailyNutrition? {
        var descriptor = FetchDescriptor<DailyNutrition>(
            predicate: #Predicate { $0.date == day }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @MainActor
    static func count(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<DailyNutrition>())
    }
}
