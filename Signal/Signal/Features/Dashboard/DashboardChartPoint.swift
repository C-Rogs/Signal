import Foundation

struct DashboardChartPoint: Identifiable, Sendable, Equatable {
    let date: Date
    let value: Double

    var id: Date { date }
}

enum DashboardSeriesBuilder {
    static func points(
        from metrics: [DailyMetricSnapshot],
        days: Int,
        referenceDay: Date,
        calendar: Calendar,
        value: (DailyMetricSnapshot) -> Double?
    ) -> [DashboardChartPoint] {
        guard days > 0,
              let start = calendar.date(
                  byAdding: .day,
                  value: -(days - 1),
                  to: calendar.startOfDay(for: referenceDay)
              )
        else { return [] }

        let end = calendar.startOfDay(for: referenceDay)
        return metrics
            .filter {
                let day = calendar.startOfDay(for: $0.date)
                return day >= start && day <= end
            }
            .compactMap { snapshot -> DashboardChartPoint? in
                guard let value = value(snapshot) else { return nil }
                return DashboardChartPoint(date: snapshot.date, value: value)
            }
            .sorted { $0.date < $1.date }
    }

    static func latestValue(in points: [DashboardChartPoint]) -> Double? {
        points.last?.value
    }
}

extension Array where Element == DashboardChartPoint {
    var chartRenderIdentity: String {
        guard let first = first, let last = last else { return "empty" }
        return "\(count)-\(first.date.timeIntervalSince1970)-\(last.date.timeIntervalSince1970)-\(last.value)"
    }

    var chartDateDomain: ClosedRange<Date> {
        guard let first = first?.date, let last = last?.date else {
            let now = Date()
            return now ... now
        }
        if first == last {
            return first ... last.addingTimeInterval(86_400)
        }
        return first ... last
    }

    var chartValueDomain: ClosedRange<Double> {
        let values = map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0 ... 1
        }
        if minValue == maxValue {
            let padding = Swift.max(abs(minValue) * 0.1, 1)
            return (minValue - padding) ... (maxValue + padding)
        }
        let span = maxValue - minValue
        let padding = span * 0.08
        return (minValue - padding) ... (maxValue + padding)
    }
}
