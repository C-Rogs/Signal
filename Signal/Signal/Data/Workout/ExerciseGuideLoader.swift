import Foundation
import os

struct HevyExerciseGuideEntry: Codable, Sendable {
    let hevyTitle: String
    let canonicalName: String
    let instructions: [String]
    let sourceExerciseId: String?
}

private struct HevyExerciseGuidesBundle: Codable, Sendable {
    let version: Int
    let guides: [HevyExerciseGuideEntry]
}

enum ExerciseGuideLoader {
    private static let resourceName = "HevyExerciseGuides"
    private static let resourceExtension = "json"

    private static var cachedBundle: HevyExerciseGuidesBundle?

    static func guide(for catalogEntry: ExerciseCatalog?) -> [String]? {
        guard let catalogEntry else { return nil }
        return guide(forCanonicalName: catalogEntry.canonicalName)
            ?? guide(forHevyTitle: catalogEntry.canonicalName)
    }

    static func guide(for exerciseTitle: String) -> [String]? {
        let trimmed = exerciseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return guide(forHevyTitle: trimmed)
            ?? guide(forCanonicalName: trimmed)
    }

    static func loadedGuideCount() -> Int {
        (try? loadBundle())?.guides.count ?? 0
    }

    static func resetCacheForTesting() {
        cachedBundle = nil
    }

    private static func guide(forHevyTitle title: String) -> [String]? {
        let normalized = ExerciseTitleNormalizer.normalize(title)
        guard let bundle = try? loadBundle() else { return nil }
        if let exact = bundle.guides.first(where: {
            ExerciseTitleNormalizer.normalize($0.hevyTitle) == normalized
        }) {
            return instructionsOrNil(exact)
        }
        return nil
    }

    private static func guide(forCanonicalName name: String) -> [String]? {
        let normalized = ExerciseTitleNormalizer.normalize(name)
        guard let bundle = try? loadBundle() else { return nil }
        if let exact = bundle.guides.first(where: {
            ExerciseTitleNormalizer.normalize($0.canonicalName) == normalized
        }) {
            return instructionsOrNil(exact)
        }
        return nil
    }

    private static func instructionsOrNil(_ entry: HevyExerciseGuideEntry) -> [String]? {
        let steps = entry.instructions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return steps.isEmpty ? nil : steps
    }

    private static func loadBundle() throws -> HevyExerciseGuidesBundle {
        if let cachedBundle {
            return cachedBundle
        }
        guard let url = resourceURL() else {
            Log.catalog.error("missing bundled HevyExerciseGuides.json")
            throw GuideLoaderError.missingBundledData
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(HevyExerciseGuidesBundle.self, from: data)
        cachedBundle = decoded
        Log.catalog.info("loaded hevy exercise guides count=\(decoded.guides.count, privacy: .public)")
        return decoded
    }

    private static func resourceURL() -> URL? {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) {
            return url
        }
        #if DEBUG
        return Bundle(for: BundleToken.self).url(forResource: resourceName, withExtension: resourceExtension)
        #else
        return nil
        #endif
    }

    enum GuideLoaderError: Error {
        case missingBundledData
    }

    private final class BundleToken {}
}
