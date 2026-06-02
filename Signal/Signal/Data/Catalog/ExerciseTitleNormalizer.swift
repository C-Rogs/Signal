import Foundation

enum ExerciseTitleNormalizer: Sendable {
    nonisolated static func normalize(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.precomposedStringWithCompatibilityMapping
        text = stripEmoji(text)
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        text = String(text.unicodeScalars.map { scalar in
            if allowed.contains(scalar) {
                Character(scalar)
            } else {
                " "
            }
        })
        text = text.lowercased()
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text
    }

    nonisolated static func parseHevyStyle(_ title: String) -> (base: String, equipment: ExerciseEquipment?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.lastIndex(of: "("),
              trimmed.hasSuffix(")"),
              open > trimmed.startIndex
        else {
            return (normalize(trimmed), nil)
        }
        let basePart = String(trimmed[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        let equipPart = String(trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)])
        return (normalize(basePart), mapHevyEquipmentLabel(equipPart))
    }

    nonisolated private static func mapHevyEquipmentLabel(_ label: String) -> ExerciseEquipment? {
        let key = normalize(label)
        switch key {
        case "barbell": return .barbell
        case "dumbbell": return .dumbbell
        case "machine", "machine plates": return .machine
        case "cable": return .cable
        case "bodyweight": return .bodyweight
        case "kettlebell": return .kettlebell
        case "band": return .band
        case "smith machine", "smith": return .smith
        default: return .other
        }
    }

    nonisolated private static func stripEmoji(_ text: String) -> String {
        text.filter { character in
            guard let scalar = character.unicodeScalars.first else { return true }
            return !scalar.properties.isEmojiPresentation && scalar.value < 0x1F000
        }
    }
}
