import Foundation
import Observation

@MainActor
@Observable
final class RecoveryPreferences {
    static let shared = RecoveryPreferences()

    var calendarHintPhrases: [String] {
        didSet { persistCalendarHintPhrases() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        calendarHintPhrases = Self.normalizedPhrases(
            defaults.stringArray(forKey: Self.calendarHintPhrasesKey) ?? []
        )
    }

    func addCalendarHintPhrase(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = calendarHintPhrases
        let lower = trimmed.lowercased()
        guard !updated.contains(where: { $0.lowercased() == lower }) else { return }
        updated.append(trimmed)
        calendarHintPhrases = Self.normalizedPhrases(updated)
    }

    func removeCalendarHintPhrase(at index: Int) {
        guard calendarHintPhrases.indices.contains(index) else { return }
        var updated = calendarHintPhrases
        updated.remove(at: index)
        calendarHintPhrases = updated
    }

    private func persistCalendarHintPhrases() {
        defaults.set(calendarHintPhrases, forKey: Self.calendarHintPhrasesKey)
    }

    private static func normalizedPhrases(_ phrases: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for phrase in phrases {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static let calendarHintPhrasesKey = "signal.recovery.calendarHintPhrases"
}
