import Foundation
import os

struct CatalogMatchRow: Sendable {
    let importedTitle: String
    let canonicalName: String?
    let primaryMuscles: [Muscle]
    let secondaryMuscles: [Muscle]
    let flag: CatalogMatchFlag
    let confidence: Double
}

struct CatalogMatchReport: Sendable {
    let matched: [CatalogMatchRow]
    let review: [CatalogMatchRow]

    var matchTableLines: [String] {
        matched.map { row in
            let primary = row.primaryMuscles.map(\.rawValue).joined(separator: ", ")
            let secondary = row.secondaryMuscles.map(\.rawValue).joined(separator: ", ")
            return "\(row.importedTitle) -> \(row.canonicalName ?? "?") [\(primary)] sec [\(secondary)] (\(row.flag.rawValue) \(String(format: "%.2f", row.confidence)))"
        }
    }

    var reviewLines: [String] {
        review.map { row in
            if let canonical = row.canonicalName {
                return "REVIEW: \(row.importedTitle) -> \(canonical) (\(row.flag.rawValue) \(String(format: "%.2f", row.confidence)))"
            }
            return "UNMATCHED: \(row.importedTitle) (confidence \(String(format: "%.2f", row.confidence)))"
        }
    }
}

@MainActor
enum CatalogMatchReporter {
    static let geminiImportSampleTitles: [String] = [
        "Wide-Grip Lat Pulldown (Upper Lat Flush)",
        "Dumbbell Bicep Curl",
        "Machine Chest Press (Supported Pectoral Drive)",
        "Dumbbell Lateral Raise",
        "Cable Triceps Extension",
        "Lat Pulldown",
    ]

    static func buildReport(for titles: [String], catalog: [ExerciseCatalog]) -> CatalogMatchReport {
        let unique = Array(Set(titles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
        let index = ExerciseCatalogMatcher.buildAliasIndex(catalog: catalog)
        var matched: [CatalogMatchRow] = []
        var review: [CatalogMatchRow] = []

        for title in unique {
            let result = ExerciseCatalogMatcher.match(
                importedTitle: title,
                catalog: catalog,
                aliasIndex: index
            )
            let row = CatalogMatchRow(
                importedTitle: title,
                canonicalName: result.entry?.canonicalName,
                primaryMuscles: result.entry?.primaryMuscles ?? [],
                secondaryMuscles: result.entry?.secondaryMuscles ?? [],
                flag: result.flag,
                confidence: result.confidence
            )
            switch result.flag {
            case .matched:
                matched.append(row)
            case .lowConfidence, .unmatched:
                review.append(row)
            }
        }

        Log.catalog.info("catalog match report matched=\(matched.count) review=\(review.count)")
        for line in matched.prefix(5) {
            Log.catalog.debug("\(line.importedTitle, privacy: .public)")
        }
        for line in review {
            Log.catalog.notice("\(line.importedTitle, privacy: .public) flag=\(line.flag.rawValue, privacy: .public)")
        }

        return CatalogMatchReport(matched: matched, review: review)
    }
}
