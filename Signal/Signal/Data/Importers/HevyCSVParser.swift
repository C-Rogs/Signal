import Foundation
import os

enum HevyCSVParser {
    static func parse(
        fileURL: URL,
        calendar: Calendar
    ) throws -> HevyCSVParseResult {
        let hasScope = fileURL.startAccessingSecurityScopedResource()
        if !hasScope {
            Log.import.warning("security-scoped access not granted; attempting Hevy CSV parse anyway")
        }
        defer {
            if hasScope {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw HevyCSVParseError.cannotReadFile
        }
        return try parse(data: data, calendar: calendar)
    }

    static func parse(data: Data, calendar: Calendar) throws -> HevyCSVParseResult {
        guard !data.isEmpty else {
            throw HevyCSVParseError.emptyFile
        }

        let started = Date()
        let rows = try RFC4180CSVParser.parseRecords(from: data)
        guard let headerRow = rows.first else {
            throw HevyCSVParseError.missingHeaderRow
        }
        guard rows.count > 1 else {
            throw HevyCSVParseError.noDataRows
        }

        let columnIndex = try Self.buildColumnIndex(headerRow: headerRow)
        let setRows = try Self.parseSetRows(
            dataRows: rows.dropFirst(),
            columnIndex: columnIndex,
            calendar: calendar
        )
        let sessions = Self.buildSessions(from: setRows, calendar: calendar)
        let affectedDays = Array(Set(sessions.map(\.dayStart))).sorted()

        let elapsed = Date().timeIntervalSince(started)
        Log.import.info(
            "Hevy CSV parse rows=\(setRows.count, privacy: .public) sessions=\(sessions.count, privacy: .public) days=\(affectedDays.count, privacy: .public) elapsedSec=\(elapsed, format: .fixed(precision: 2), privacy: .public)"
        )

        return HevyCSVParseResult(
            headerColumns: headerRow,
            rowsParsed: setRows.count,
            sessions: sessions,
            affectedDayStarts: affectedDays
        )
    }

    private static func buildColumnIndex(headerRow: [String]) throws -> [String: Int] {
        var index: [String: Int] = [:]
        for (offset, raw) in headerRow.enumerated() {
            let key = HevyCSVRecordTypes.normalizeHeader(raw)
            if !key.isEmpty {
                index[key] = offset
            }
        }
        try HevyCSVRecordTypes.validateHeaders(columnIndex: index, rawHeader: headerRow)
        return index
    }

    private struct RawSetRow {
        let title: String
        let sessionDescription: String?
        let startTime: Date
        let endTime: Date?
        let exerciseTitle: String
        let supersetId: String?
        let exerciseNotes: String?
        let setIndex: Int
        let setType: String
        let weightKg: Double?
        let reps: Int?
        let distanceKm: Double?
        let durationSeconds: Int?
        let rpe: Double?
    }

    private static func parseSetRows(
        dataRows: ArraySlice<[String]>,
        columnIndex: [String: Int],
        calendar: Calendar
    ) throws -> [RawSetRow] {
        var result: [RawSetRow] = []
        result.reserveCapacity(dataRows.count)

        for (offset, row) in dataRows.enumerated() {
            let rowNumber = offset + 2
            guard let startRaw = field("start_time", in: row, columnIndex: columnIndex),
                  let startTime = HevyDateParser.parse(startRaw, calendar: calendar)
            else {
                throw HevyCSVParseError.missingStartTime(row: rowNumber)
            }

            let endRaw = field("end_time", in: row, columnIndex: columnIndex)
            let endTime = endRaw.flatMap { HevyDateParser.parse($0, calendar: calendar) }

            let setIndex = intField("set_index", in: row, columnIndex: columnIndex) ?? offset

            result.append(
                RawSetRow(
                    title: field("title", in: row, columnIndex: columnIndex) ?? "",
                    sessionDescription: field("description", in: row, columnIndex: columnIndex),
                    startTime: startTime,
                    endTime: endTime,
                    exerciseTitle: field("exercise_title", in: row, columnIndex: columnIndex) ?? "",
                    supersetId: field("superset_id", in: row, columnIndex: columnIndex),
                    exerciseNotes: field("exercise_notes", in: row, columnIndex: columnIndex),
                    setIndex: setIndex,
                    setType: field("set_type", in: row, columnIndex: columnIndex) ?? "normal",
                    weightKg: weightKgField(in: row, columnIndex: columnIndex),
                    reps: intField("reps", in: row, columnIndex: columnIndex),
                    distanceKm: distanceKmField(in: row, columnIndex: columnIndex),
                    durationSeconds: intField("duration_seconds", in: row, columnIndex: columnIndex),
                    rpe: doubleField("rpe", in: row, columnIndex: columnIndex)
                )
            )
        }
        return result
    }

    private static func buildSessions(
        from rows: [RawSetRow],
        calendar: Calendar
    ) -> [HevyParsedSession] {
        struct SessionKey: Hashable {
            let title: String
            let startTime: Date
        }

        var grouped: [SessionKey: [RawSetRow]] = [:]
        for row in rows {
            let key = SessionKey(title: row.title, startTime: row.startTime)
            grouped[key, default: []].append(row)
        }

        return grouped.map { key, sessionRows in
            let dayStart = calendar.startOfDay(for: key.startTime)
            let first = sessionRows[0]
            let endTime = sessionRows.compactMap(\.endTime).max()
            let exercises = Self.buildExercises(from: sessionRows)
            return HevyParsedSession(
                title: key.title,
                sessionDescription: first.sessionDescription,
                startTime: key.startTime,
                endTime: endTime,
                dayStart: dayStart,
                exercises: exercises
            )
        }
        .sorted { $0.startTime < $1.startTime }
    }

    private static func buildExercises(from rows: [RawSetRow]) -> [HevyParsedExercise] {
        struct ExerciseKey: Hashable {
            let title: String
            let supersetId: String?
        }

        var orderCounter = 0
        var exerciseOrder: [ExerciseKey: Int] = [:]
        var grouped: [ExerciseKey: [RawSetRow]] = [:]

        for row in rows {
            let name = row.exerciseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = ExerciseKey(title: name, supersetId: row.supersetId)
            if exerciseOrder[key] == nil {
                exerciseOrder[key] = orderCounter
                orderCounter += 1
            }
            grouped[key, default: []].append(row)
        }

        return exerciseOrder.keys.sorted { exerciseOrder[$0]! < exerciseOrder[$1]! }.compactMap { key in
            guard let exerciseRows = grouped[key] else { return nil }
            let sortedSets = exerciseRows.sorted { $0.setIndex < $1.setIndex }
            let sets = sortedSets.map { row in
                HevyParsedSet(
                    setIndex: row.setIndex,
                    setType: row.setType,
                    weightKg: row.weightKg,
                    reps: row.reps,
                    distanceKm: row.distanceKm,
                    durationSeconds: row.durationSeconds,
                    rpe: row.rpe
                )
            }
            let notes = exerciseRows.compactMap(\.exerciseNotes).first { !$0.isEmpty }
            return HevyParsedExercise(
                exerciseTitle: key.title,
                notes: notes,
                supersetId: key.supersetId,
                order: exerciseOrder[key] ?? 0,
                sets: sets
            )
        }
    }

    private static func weightKgField(in row: [String], columnIndex: [String: Int]) -> Double? {
        if let kg = doubleField("weight_kg", in: row, columnIndex: columnIndex) {
            return kg
        }
        guard let lbs = doubleField("weight_lbs", in: row, columnIndex: columnIndex) else {
            return nil
        }
        return lbs / 2.20462
    }

    private static func distanceKmField(in row: [String], columnIndex: [String: Int]) -> Double? {
        if let km = doubleField("distance_km", in: row, columnIndex: columnIndex) {
            return km
        }
        guard let miles = doubleField("distance_miles", in: row, columnIndex: columnIndex) else {
            return nil
        }
        return miles * 1.60934
    }

    private static func field(_ name: String, in row: [String], columnIndex: [String: Int]) -> String? {
        guard let index = columnIndex[name], index < row.count else { return nil }
        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func doubleField(_ name: String, in row: [String], columnIndex: [String: Int]) -> Double? {
        guard let raw = field(name, in: row, columnIndex: columnIndex) else { return nil }
        return Double(raw)
    }

    private static func intField(_ name: String, in row: [String], columnIndex: [String: Int]) -> Int? {
        guard let raw = field(name, in: row, columnIndex: columnIndex) else { return nil }
        return Int(raw)
    }
}
