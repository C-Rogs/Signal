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

    nonisolated static func stripParentheticals(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        while let open = result.lastIndex(of: "("),
              result.hasSuffix(")"),
              open > result.startIndex {
            result = String(result[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    nonisolated static func parseImportedTitle(_ title: String) -> (base: String, equipment: ExerciseEquipment?) {
        let stripped = stripParentheticals(title)
        let hevy = parseHevyStyle(stripped)
        if hevy.equipment != nil {
            return hevy
        }
        return parseEquipmentPrefix(stripped)
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

    nonisolated static func parseEquipmentPrefix(_ title: String) -> (base: String, equipment: ExerciseEquipment?) {
        let normalized = normalize(title)
        let prefixes: [(String, ExerciseEquipment)] = [
            ("smith machine ", .smith),
            ("barbell ", .barbell),
            ("dumbbell ", .dumbbell),
            ("cable ", .cable),
            ("machine ", .machine),
            ("kettlebell ", .kettlebell),
            ("band ", .band),
        ]
        for (prefix, equipment) in prefixes where normalized.hasPrefix(prefix) {
            let base = String(normalized.dropFirst(prefix.count))
            guard !base.isEmpty else { return (normalized, nil) }
            return (base, equipment)
        }
        return (normalized, nil)
    }

    nonisolated static func matchingBase(from parsedBase: String) -> String {
        let tokens = parsedBase.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return parsedBase }
        var index = 0
        if tokens.count >= 2, gripLeadTokens.contains(tokens[0]), tokens[1] == "grip" {
            index = 2
        }
        let trimmed = tokens.dropFirst(index).filter { !optionalModifierTokens.contains($0) }
        return trimmed.isEmpty ? parsedBase : trimmed.joined(separator: " ")
    }

    nonisolated private static let gripLeadTokens: Set<String> = ["wide", "close", "narrow", "neutral", "reverse"]

    nonisolated private static let optionalModifierTokens: Set<String> = ["supported", "flush", "drive"]

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
