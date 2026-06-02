import Foundation

enum DashboardFormatting {
    static func recoveryScore(_ score: Double?) -> String {
        guard let score else { return "—" }
        return "\(Int(score.rounded()))"
    }

    static func hrv(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) ms"
    }

    static func heartRate(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) bpm"
    }

    static func energy(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) kcal"
    }

    static func sleep(_ hours: Double?) -> String {
        guard let hours else { return "—" }
        return String(format: "%.1f h", hours)
    }

    static func bodyMass(_ kg: Double?, formatter: DisplayUnitFormatter) -> String {
        formatter.formatMassKg(kg)
    }

    static func distanceKm(_ km: Double?, formatter: DisplayUnitFormatter) -> String {
        formatter.formatDistanceKm(km)
    }

    static func steps(_ count: Double?) -> String {
        guard let count else { return "—" }
        return "\(Int(count.rounded()))"
    }

    static func minutes(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) min"
    }

    static func calories(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) kcal"
    }

    static func protein(_ grams: Double?) -> String {
        guard let grams else { return "—" }
        return "\(Int(grams.rounded())) g protein"
    }
}
