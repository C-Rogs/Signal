import Foundation

enum CatalogAliasGenerator {
    static func aliases(for entry: ExerciseCatalog) -> [String] {
        var result: [String] = []
        result.append(ExerciseTitleNormalizer.normalize(entry.canonicalName))
        result.append(contentsOf: entry.aliases.map(ExerciseTitleNormalizer.normalize))

        if let hevyStyle = hevyStyleTitle(canonicalName: entry.canonicalName, equipment: entry.equipment) {
            result.append(ExerciseTitleNormalizer.normalize(hevyStyle))
            for variant in simplifiedHevyAliases(from: hevyStyle) {
                result.append(ExerciseTitleNormalizer.normalize(variant))
            }
        }

        let compactPullUpAliases = pullUpAliases(canonicalName: entry.canonicalName)
        result.append(contentsOf: compactPullUpAliases.map(ExerciseTitleNormalizer.normalize))

        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted && !$0.isEmpty }
    }

    static func hevyStyleTitle(canonicalName: String, equipment: ExerciseEquipment) -> String? {
        let display = ExerciseEquipmentMapper.hevyDisplayName(for: equipment)
        guard display != "Other", display != "Bodyweight" else { return nil }

        let name = canonicalName
        let prefixes = [
            "Barbell ", "Dumbbell ", "Cable ", "Machine ", "Kettlebell ", "Band ", "Smith Machine ",
        ]
        var base = name
        for prefix in prefixes where base.hasPrefix(prefix) {
            base = String(base.dropFirst(prefix.count))
            break
        }
        guard !base.isEmpty else { return nil }
        return "\(base) (\(display))"
    }

    static func simplifiedHevyAliases(from hevyTitle: String) -> [String] {
        let trimmed = hevyTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.lastIndex(of: "("), trimmed.hasSuffix(")") else { return [] }
        var base = String(trimmed[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(trimmed[open...])
        if let dash = base.range(of: " - ") {
            base = String(base[..<dash.lowerBound])
        }
        let simplified = "\(base) \(suffix)"
        var results = [simplified]
        if base.hasSuffix("s"), base.count > 3 {
            let singularBase = String(base.dropLast())
            results.append("\(singularBase) \(suffix)")
        }
        return results
    }

    private static func pullUpAliases(canonicalName: String) -> [String] {
        let lower = canonicalName.lowercased()
        if lower == "pullups" || lower == "weighted pull ups" {
            return ["Pull Up", "Pull-Up"]
        }
        return []
    }
}
