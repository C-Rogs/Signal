import Foundation

struct ProteinTarget: Sendable, Equatable {
    let bodyweightKg: Double
    let targetMinGrams: Double
    let targetMaxGrams: Double
    let actualGrams: Double?

    init?(bodyweightKg: Double?, actualGrams: Double? = nil) {
        guard let bodyweightKg, bodyweightKg > 0 else { return nil }
        self.bodyweightKg = bodyweightKg
        targetMinGrams = bodyweightKg * 1.6
        targetMaxGrams = bodyweightKg * 2.2
        self.actualGrams = actualGrams
    }

    var gramsPerKgActual: Double? {
        guard let actualGrams, bodyweightKg > 0 else { return nil }
        return actualGrams / bodyweightKg
    }
}
