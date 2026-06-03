import Foundation
import SwiftData

@Model
final class SyncAnchor {
    @Attribute(.unique) var hkTypeIdentifier: String
    var anchorData: Data

    init(hkTypeIdentifier: String, anchorData: Data) {
        self.hkTypeIdentifier = hkTypeIdentifier
        self.anchorData = anchorData
    }
}

enum SyncAnchorStore {
    static func upsert(
        hkTypeIdentifier: String,
        anchorData: Data,
        in context: ModelContext
    ) throws {
        let identifier = hkTypeIdentifier
        var descriptor = FetchDescriptor<SyncAnchor>(
            predicate: #Predicate { $0.hkTypeIdentifier == identifier }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.anchorData = anchorData
        } else {
            context.insert(SyncAnchor(hkTypeIdentifier: hkTypeIdentifier, anchorData: anchorData))
        }
        try context.save()
    }

    static func anchorData(
        for hkTypeIdentifier: String,
        in context: ModelContext
    ) throws -> Data? {
        let identifier = hkTypeIdentifier
        var descriptor = FetchDescriptor<SyncAnchor>(
            predicate: #Predicate { $0.hkTypeIdentifier == identifier }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.anchorData
    }

    static func deleteAll(in context: ModelContext) throws -> Int {
        let anchors = try context.fetch(FetchDescriptor<SyncAnchor>())
        let count = anchors.count
        for anchor in anchors {
            context.delete(anchor)
        }
        if count > 0 {
            try context.save()
        }
        return count
    }
}
