import Foundation

enum QueryRetrievalMode: Sendable, Equatable {
    case fixedWindow(TemporalQueryWindow)
    case recencyRanking
    case pureCosine

    static func resolve(
        in query: String,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> QueryRetrievalMode {
        if let window = TemporalQueryParser.window(
            in: query,
            referenceDate: referenceDate,
            calendar: calendar
        ) {
            return .fixedWindow(window)
        }
        if TemporalQueryParser.hasRecencyIntent(
            in: query,
            referenceDate: referenceDate,
            calendar: calendar
        ) {
            return .recencyRanking
        }
        return .pureCosine
    }
}
