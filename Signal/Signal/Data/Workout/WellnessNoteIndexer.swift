import Foundation
import os
import SwiftData

@MainActor
enum WellnessNoteIndexer {
    private static let metricKind = "wellness-note"

    static func indexNotesIfNeeded(
        entry: WellnessEntry,
        store: any VectorStore,
        service: any EmbeddingService
    ) async {
        guard let notes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
              !notes.isEmpty
        else { return }

        let dayKey = Summarizer.dayKey(for: entry.capturedAt, calendar: .current)
        let summary = "Wellness note: \(notes)"
        do {
            try await EmbeddingVectorStoreBridge.indexDocument(
                summaryText: summary,
                dayKey: dayKey,
                metricKind: metricKind,
                store: store,
                service: service
            )
        } catch {
            Log.embedding.error(
                "wellness note index failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
