import Foundation

struct CatalogMatchResult: Sendable {
    let entry: ExerciseCatalog?
    let flag: CatalogMatchFlag
    let confidence: Double
}

enum ExerciseCatalogMatcher {
    private static let highConfidenceThreshold = 0.82
    private static let lowConfidenceThreshold = 0.7

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
        let index = aliasIndex ?? buildAliasIndex(catalog: catalog)
        let normalizedFull = ExerciseTitleNormalizer.normalize(importedTitle)

        if let exact = index[normalizedFull] {
            return CatalogMatchResult(entry: exact, flag: .matched, confidence: 1)
        }

        let stripped = ExerciseTitleNormalizer.stripParentheticals(importedTitle)
        let normalized = ExerciseTitleNormalizer.normalize(stripped)

        if stripped != importedTitle, let exact = index[normalized] {
            return CatalogMatchResult(entry: exact, flag: .matched, confidence: 1)
        }

        let parsed = ExerciseTitleNormalizer.parseImportedTitle(stripped)
        let matchingBase = ExerciseTitleNormalizer.matchingBase(from: parsed.base)

        if parsed.base == "running" || parsed.base == "treadmill" || parsed.base == "cycling" {
            if let cardio = bestCardioMatch(base: parsed.base, catalog: catalog) {
                return CatalogMatchResult(entry: cardio, flag: .matched, confidence: 0.9)
            }
        }

        if isLateralRaiseBase(matchingBase), parsed.equipment == .dumbbell,
           let side = catalog.first(where: {
               $0.equipment == .dumbbell && $0.canonicalName.lowercased().contains("side lateral raise")
           }) {
            return CatalogMatchResult(entry: side, flag: .matched, confidence: 0.95)
        }

        if isMachineChestPress(parsedBase: parsed.base, equipment: parsed.equipment),
           let press = bestMachineChestPressMatch(catalog: catalog) {
            return CatalogMatchResult(entry: press, flag: .matched, confidence: 0.93)
        }

        if isCableTricepsExtension(parsedBase: parsed.base, equipment: parsed.equipment),
           let pushdown = bestCableTricepsMatch(catalog: catalog) {
            return CatalogMatchResult(entry: pushdown, flag: .matched, confidence: 0.93)
        }

        var best: (entry: ExerciseCatalog, score: Double)?

        for entry in catalog {
            let score = fuzzyScore(
                parsedBase: parsed.base,
                matchingBase: matchingBase,
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

    private static func isLateralRaiseBase(_ base: String) -> Bool {
        base == "lateral raise" || base.hasSuffix(" lateral raise")
    }

    private static func isMachineChestPress(parsedBase: String, equipment: ExerciseEquipment?) -> Bool {
        guard equipment == .machine || parsedBase.hasPrefix("machine ") else { return false }
        let base = parsedBase.hasPrefix("machine ") ? String(parsedBase.dropFirst("machine ".count)) : parsedBase
        return base == "chest press" || base == "press machine"
    }

    private static func isCableTricepsExtension(parsedBase: String, equipment: ExerciseEquipment?) -> Bool {
        guard equipment == .cable else { return false }
        return parsedBase.contains("tricep") && parsedBase.contains("extension")
    }

    private static func bestMachineChestPressMatch(catalog: [ExerciseCatalog]) -> ExerciseCatalog? {
        let candidates = catalog.filter {
            $0.equipment == .machine && $0.canonicalName.lowercased().contains("chest press")
                || $0.canonicalName.lowercased() == "machine bench press"
        }
        return candidates.first { $0.canonicalName.lowercased() == "machine bench press" }
            ?? candidates.first { $0.canonicalName.lowercased().contains("chest press") }
    }

    private static func bestCableTricepsMatch(catalog: [ExerciseCatalog]) -> ExerciseCatalog? {
        catalog.first { $0.canonicalName.lowercased() == "triceps pushdown" }
            ?? catalog.first {
                $0.equipment == .cable && $0.canonicalName.lowercased().contains("triceps")
                    && ($0.canonicalName.lowercased().contains("pushdown")
                        || $0.canonicalName.lowercased().contains("extension"))
            }
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
        matchingBase: String,
        parsedEquipment: ExerciseEquipment?,
        entry: ExerciseCatalog
    ) -> Double {
        let canonicalNorm = ExerciseTitleNormalizer.normalize(entry.canonicalName)
        let canonicalMatchingBase = ExerciseTitleNormalizer.matchingBase(from: canonicalNorm)
        let baseTokens = matchingBase.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !baseTokens.isEmpty else { return 0 }

        guard baseTokensMatch(baseTokens, in: canonicalMatchingBase) || baseTokensMatch(baseTokens, in: canonicalNorm) else {
            return 0
        }

        let entryTokens = Set(canonicalMatchingBase.split(separator: " ").map(String.init))
        let baseSet = Set(baseTokens.flatMap(tokenVariants))
        let intersection = baseSet.intersection(entryTokens).count
        let union = baseSet.union(entryTokens).count
        var score = union > 0 ? Double(intersection) / Double(union) : 0

        if let parsedEquipment {
            if entry.equipment == parsedEquipment {
                score += 0.25
            } else if !equipmentCompatible(parsed: parsedEquipment, entry: entry.equipment) {
                return 0
            }
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

        for alias in CatalogAliasGenerator.geminiStyleAliases(
            canonicalName: entry.canonicalName,
            equipment: entry.equipment
        ) {
            let aliasNorm = ExerciseTitleNormalizer.normalize(alias)
            if aliasNorm == ExerciseTitleNormalizer.normalize(strippedImportedTitle(parsedBase, equipment: parsedEquipment)) {
                score = max(score, 0.95)
            }
        }

        return min(score, 1)
    }

    private static func strippedImportedTitle(_ base: String, equipment: ExerciseEquipment?) -> String {
        guard let equipment else { return base }
        let display = ExerciseEquipmentMapper.hevyDisplayName(for: equipment)
        return "\(display) \(base)"
    }

    private static func equipmentCompatible(parsed: ExerciseEquipment, entry: ExerciseEquipment) -> Bool {
        if parsed == entry { return true }
        if parsed == .machine, entry == .smith { return true }
        return false
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
        var variants: [String] = [token]
        if token.count > 3, token.hasSuffix("s") {
            variants.append(String(token.dropLast()))
        } else if !token.hasSuffix("s") {
            variants.append(token + "s")
        }
        switch token {
        case "bicep": variants.append("biceps")
        case "biceps": variants.append("bicep")
        case "tricep": variants.append("triceps")
        case "triceps": variants.append("tricep")
        case "extension":
            variants.append("pushdown")
        case "pushdown":
            variants.append("extension")
        case "chest":
            variants.append("bench")
        case "bench":
            variants.append("chest")
        default:
            break
        }
        return Array(Set(variants))
    }
}
