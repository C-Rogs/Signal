import Foundation
import os

enum HevyCSVRecordTypes {
    static let requiredColumns: Set<String> = [
        "title",
        "start_time",
        "exercise_title",
    ]

    static let expectedColumns: Set<String> = [
        "title",
        "start_time",
        "end_time",
        "description",
        "exercise_title",
        "superset_id",
        "exercise_notes",
        "set_index",
        "set_type",
        "weight_kg",
        "reps",
        "distance_km",
        "duration_seconds",
        "rpe",
    ]

    static let knownColumns: Set<String> = expectedColumns.union([
        "weight_lbs",
        "distance_miles",
    ])

    static func normalizeHeader(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    static func validateHeaders(columnIndex: [String: Int], rawHeader: [String]) throws {
        let missingRequired = requiredColumns.filter { columnIndex[$0] == nil }
        if !missingRequired.isEmpty {
            throw HevyCSVParseError.unexpectedHeaders(
                found: rawHeader.joined(separator: ","),
                missing: missingRequired.sorted()
            )
        }

        var missingExpected = expectedColumns.filter { columnIndex[$0] == nil }
        if columnIndex["weight_kg"] != nil || columnIndex["weight_lbs"] != nil {
            missingExpected.remove("weight_kg")
        }
        if columnIndex["distance_km"] != nil || columnIndex["distance_miles"] != nil {
            missingExpected.remove("distance_km")
        }
        if !missingExpected.isEmpty {
            throw HevyCSVParseError.unexpectedHeaders(
                found: rawHeader.joined(separator: ","),
                missing: missingExpected.sorted()
            )
        }
    }
}

enum HevyDateParser {
    static func parse(_ string: String, calendar: Calendar) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let primary = DateFormatter()
        primary.locale = Locale(identifier: "en_US_POSIX")
        primary.timeZone = calendar.timeZone
        primary.dateFormat = "d MMM yyyy, HH:mm"

        let withSeconds = DateFormatter()
        withSeconds.locale = Locale(identifier: "en_US_POSIX")
        withSeconds.timeZone = calendar.timeZone
        withSeconds.dateFormat = "d MMM yyyy, HH:mm:ss"

        if let date = primary.date(from: trimmed) {
            return date
        }
        return withSeconds.date(from: trimmed)
    }
}

struct HevyParsedSet: Sendable, Equatable {
    let setIndex: Int
    let setType: String
    let weightKg: Double?
    let reps: Int?
    let distanceKm: Double?
    let durationSeconds: Int?
    let rpe: Double?
}

struct HevyParsedExercise: Sendable, Equatable {
    let exerciseTitle: String
    let notes: String?
    let supersetId: String?
    let order: Int
    let sets: [HevyParsedSet]
}

struct HevyParsedSession: Sendable, Equatable {
    let title: String
    let sessionDescription: String?
    let startTime: Date
    let endTime: Date?
    let dayStart: Date
    let exercises: [HevyParsedExercise]
}

struct HevyCSVParseResult: Sendable {
    let headerColumns: [String]
    let rowsParsed: Int
    let sessions: [HevyParsedSession]
    let affectedDayStarts: [Date]
}

enum HevyCSVParseError: Error, Sendable {
    case cannotReadFile
    case emptyFile
    case missingHeaderRow
    case unexpectedHeaders(found: String, missing: [String])
    case noDataRows
    case missingStartTime(row: Int)
}
