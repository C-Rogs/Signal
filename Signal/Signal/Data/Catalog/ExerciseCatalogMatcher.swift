import Foundation

struct CatalogMatchResult: Sendable {
    let entry: ExerciseCatalog?
    let flag: CatalogMatchFlag
    let confidence: Double
}

enum ExerciseCatalogMatcher {
    private static let highConfidenceThreshold = 0.82
    private static let lowConfidenceThreshold = 0.58

    static func buildAliasIndex(catalog: [ExerciseCatalog]) -> [String: ExerciseCatalog] {
        var index: [String: ExerciseCatalog] = [:]
        for entry in catalog {
            let aliases = CatalogAliasGenerator.aliases(for: entry)
            for alias in aliases {
                index[alias] = entry
            }
        }
        return index
    }

    static func match(
        importedTitle: String,
        catalog: [ExerciseCatalog],
        aliasIndex: [String: ExerciseCatalog]? = nil
    ) -> CatalogMatchResult {
        let normalized = ExerciseTitleNormalizer.normalize(importedTitle)
        let index = aliasIndex ?? buildAliasIndex(catalog: catalog)

        if let exact = index[normalized] {
            return CatalogMatchResult(entry: exact, flag: .matched, confidence: 1)
        }

        let parsed = ExerciseTitleNormalizer.parseHevyStyle(importedTitle)
        if parsed.base == "running" || parsed.base == "treadmill" || parsed.base == "cycling" {
            if let cardio = bestCardioMatch(base: parsed.base, catalog: catalog) {
                return CatalogMatchResult(entry: cardio, flag: .matched, confidence: 0.9)
            }
        }

        if parsed.base == "lateral raise", parsed.equipment == .dumbbell,
           let side = catalog.first(where: {
               $0.equipment == .dumbbell && $0.canonicalName.lowercased().contains("side lateral raise")
           }) {
            return CatalogMatchResult(entry: side, flag: .matched, confidence: 0.95)
        }

        var best: (entry: ExerciseCatalog, score: Double)?

        for entry in catalog {
            let score = fuzzyScore(
                parsedBase: parsed.base,
                parsedEquipment: parsed.equipment,
                entry: entry
            )
            guard score > 0 else { continue }
            if let current = best {
                if score > current.score {
                    best = (entry, score)
                } else if score == current.score, entry.canonicalName.count < current.entry.canonicalName.count {
                    best = (entry, score)
                }
            } else {
                best = (entry, score)
            }
        }

        guard let best else {
            return CatalogMatchResult(entry: nil, flag: .unmatched, confidence: 0)
        }

        if best.score >= highConfidenceThreshold {
            return CatalogMatchResult(entry: best.entry, flag: .matched, confidence: best.score)
        }
        if best.score >= lowConfidenceThreshold {
            return CatalogMatchResult(entry: best.entry, flag: .lowConfidence, confidence: best.score)
        }
        return CatalogMatchResult(entry: nil, flag: .unmatched, confidence: best.score)
    }

    private static func bestCardioMatch(base: String, catalog: [ExerciseCatalog]) -> ExerciseCatalog? {
        let candidates = catalog.filter { $0.movementPattern == .cardio }
        if base == "running" || base == "treadmill" {
            return candidates.first { $0.canonicalName.lowercased().contains("running") }
                ?? candidates.first
        }
        if base == "cycling" {
            return candidates.first { $0.canonicalName.lowercased().contains("cycl") }
                ?? candidates.first
        }
        return candidates.first
    }

    private static func fuzzyScore(
        parsedBase: String,
        parsedEquipment: ExerciseEquipment?,
        entry: ExerciseCatalog
    ) -> Double {
        let canonicalNorm = ExerciseTitleNormalizer.normalize(entry.canonicalName)
        let baseTokens = parsedBase.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !baseTokens.isEmpty else { return 0 }

        guard baseTokensMatch(baseTokens, in: canonicalNorm) else { return 0 }

        let entryTokens = Set(canonicalNorm.split(separator: " ").map(String.init))
        let baseSet = Set(baseTokens.flatMap(tokenVariants))
        let intersection = baseSet.intersection(entryTokens).count
        let union = baseSet.union(entryTokens).count
        var score = union > 0 ? Double(intersection) / Double(union) : 0

        if let parsedEquipment {
            guard entry.equipment == parsedEquipment else { return 0 }
            score += 0.25
        }

        if let hevyStyle = CatalogAliasGenerator.hevyStyleTitle(
            canonicalName: entry.canonicalName,
            equipment: entry.equipment
        ) {
            let hevyNorm = ExerciseTitleNormalizer.normalize(hevyStyle)
            if hevyNorm == ExerciseTitleNormalizer.normalize(parsedBase) {
                score = max(score, 0.92)
            }
            for variant in CatalogAliasGenerator.simplifiedHevyAliases(from: hevyStyle) {
                if ExerciseTitleNormalizer.normalize(variant) == ExerciseTitleNormalizer.normalize(importedBaseTitle(parsedBase, equipment: parsedEquipment)) {
                    score = max(score, 0.95)
                }
            }
        }

        return min(score, 1)
    }

    private static func importedBaseTitle(_ base: String, equipment: ExerciseEquipment?) -> String {
        guard let equipment else { return base }
        return "\(base) (\(ExerciseEquipmentMapper.hevyDisplayName(for: equipment)))"
    }

    private static func baseTokensMatch(_ baseTokens: [String], in canonicalNorm: String) -> Bool {
        let entryTokens = Set(canonicalNorm.split(separator: " ").map(String.init))
        return baseTokens.allSatisfy { token in
            tokenVariants(token).contains(where: { entryTokens.contains($0) })
        }
    }

    nonisolated private static func tokenVariants(_ token: String) -> [String] {
        if token.count > 3, token.hasSuffix("s") {
            return [token, String(token.dropLast())]
        }
        if !token.hasSuffix("s") {
            return [token, token + "s"]
        }
        return [token]
    }
}
