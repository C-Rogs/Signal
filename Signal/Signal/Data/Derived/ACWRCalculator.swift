import Foundation

enum ACWRZone: String, Sendable, Equatable {
    case belowOptimal
    case optimal
    case caution
    case overreach

    var badgeLabel: String {
        switch self {
        case .belowOptimal:
            return "Below optimal"
        case .optimal:
            return "Optimal"
        case .caution:
            return "Caution"
        case .overreach:
            return "Overreach"
        }
    }
}

struct ACWRResult: Sendable, Equatable {
    let acuteLoad: Double
    let chronicLoad: Double
    let acwr: Double
    let zone: ACWRZone
}

enum ACWRCalculator {
    static func compute(dailyLoads: [(date: Date, totalSets: Int)], referenceDate: Date, calendar: Calendar) -> ACWRResult? {
        let refDay = calendar.startOfDay(for: referenceDate)
        guard let acuteStart = calendar.date(byAdding: .day, value: -6, to: refDay),
              let chronicStart = calendar.date(byAdding: .day, value: -27, to: refDay)
        else {
            return nil
        }

        var acuteLoad = 0.0
        var chronicSum = 0.0
        for entry in dailyLoads {
            let day = calendar.startOfDay(for: entry.date)
            guard day >= chronicStart, day <= refDay else { continue }
            let sets = Double(entry.totalSets)
            if day >= acuteStart {
                acuteLoad += sets
            }
            chronicSum += sets
        }

        let chronicLoad = chronicSum / 4.0
        guard chronicLoad > 0 else { return nil }
        let ratio = acuteLoad / chronicLoad
        return ACWRResult(
            acuteLoad: acuteLoad,
            chronicLoad: chronicLoad,
            acwr: ratio,
            zone: zone(for: ratio)
        )
    }

    static func zone(for acwr: Double) -> ACWRZone {
        if acwr < 0.8 {
            return .belowOptimal
        }
        if acwr <= 1.3 {
            return .optimal
        }
        if acwr <= 1.5 {
            return .caution
        }
        return .overreach
    }
}
