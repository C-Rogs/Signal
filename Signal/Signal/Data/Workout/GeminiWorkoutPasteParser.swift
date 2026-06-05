import Foundation
import os

enum GeminiWorkoutPasteParser {
    private static let lbToKg = 0.453_592_37

    private static let setLinePattern: NSRegularExpression = {
        let pattern = #"(?i)^(?:set\s+(\d+)\s*:\s*)?([\d.]+)\s*(kg|lb)(?:\s+dbs?)?\s*[x×]\s*(\d+)(?:\s*@\s*([\d.]+)(?:\s*rpe)?)?(?:\s*\(([^)]+)\))?\s*$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let restLinePattern: NSRegularExpression = {
        let pattern = #"(?i)^(?:\(?\s*)?(?:rest\s*:?\s*)?(\d+)\s*(s(?:ec(?:ond)?s?)?|m(?:in(?:ute)?s?)?)(?:\s*rest)?\s*\)?\s*$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let warmupParenPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"(?i)^warm[- ]?up$"#)
    }()

    private static let junkBeforeSetsPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"(?i)\bset\b"#)
    }()

    static func parse(_ text: String) -> ParsedWorkoutPlan {
        let rawLines = text.components(separatedBy: .newlines)
        var nonBlankLines: [(index: Int, content: String)] = []
        for (offset, line) in rawLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            nonBlankLines.append((offset, trimmed))
        }

        guard !nonBlankLines.isEmpty else {
            return ParsedWorkoutPlan(title: "Workout", exercises: [], skippedLines: [])
        }

        var skippedLines: [String] = []
        var title: String?
        var exercises: [ParsedExercise] = []
        var currentExerciseTitle: String?
        var currentSets: [ParsedWorkoutSet] = []
        var pendingExerciseRest: Int?
        var lineIndex = 0

        func flushExerciseIfNeeded() {
            guard let currentExerciseTitle, !currentSets.isEmpty else { return }
            exercises.append(
                ParsedExercise(
                    exerciseTitle: currentExerciseTitle,
                    sets: currentSets,
                    restDurationSeconds: pendingExerciseRest
                )
            )
            currentSets = []
            pendingExerciseRest = nil
        }

        if nonBlankLines.count >= 2,
           !isSetLine(nonBlankLines[0].content),
           !isRestLine(nonBlankLines[0].content),
           isSetLine(nonBlankLines[1].content) {
            let orphanSetBeforeNextExercise = nonBlankLines.count >= 3
                && !isSetLine(nonBlankLines[2].content)
                && !isRestLine(nonBlankLines[2].content)
            if orphanSetBeforeNextExercise {
                title = nonBlankLines[0].content
            } else {
                title = "Workout"
                currentExerciseTitle = nonBlankLines[0].content
            }
            lineIndex = 1
        } else {
            title = nonBlankLines[0].content
            lineIndex = 1
        }

        while lineIndex < nonBlankLines.count {
            let line = nonBlankLines[lineIndex].content
            let nextLine = lineIndex + 1 < nonBlankLines.count ? nonBlankLines[lineIndex + 1].content : nil

            if let parsedSet = parseSetLine(line, fallbackSetIndex: currentSets.count + 1) {
                guard currentExerciseTitle != nil else {
                    skippedLines.append(line)
                    lineIndex += 1
                    continue
                }
                currentSets.append(parsedSet)
            } else if let restSeconds = parseRestLine(line) {
                guard currentExerciseTitle != nil else {
                    skippedLines.append(line)
                    lineIndex += 1
                    continue
                }
                if !currentSets.isEmpty, let nextLine, isSetLine(nextLine) {
                    attachRest(restSeconds, toLastSetIn: &currentSets)
                } else {
                    pendingExerciseRest = restSeconds
                }
            } else if currentExerciseTitle != nil, currentSets.isEmpty {
                if looksLikeJunkBeforeFirstSet(line) {
                    skippedLines.append(line)
                } else {
                    currentExerciseTitle = line
                    pendingExerciseRest = nil
                }
            } else {
                flushExerciseIfNeeded()
                currentExerciseTitle = line
                pendingExerciseRest = nil
            }

            lineIndex += 1
        }

        flushExerciseIfNeeded()

        let resolvedTitle = title ?? "Workout"
        let resolvedExercises = exercises.filter { !$0.sets.isEmpty }

        Log.import.info(
            "gemini paste parsed title=\(resolvedTitle, privacy: .public) exercises=\(resolvedExercises.count, privacy: .public) skipped=\(skippedLines.count, privacy: .public)"
        )

        return ParsedWorkoutPlan(
            title: resolvedTitle,
            exercises: resolvedExercises,
            skippedLines: skippedLines
        )
    }

    private static func attachRest(_ seconds: Int, toLastSetIn sets: inout [ParsedWorkoutSet]) {
        guard let last = sets.popLast() else { return }
        sets.append(
            ParsedWorkoutSet(
                setIndex: last.setIndex,
                weightKg: last.weightKg,
                reps: last.reps,
                rpe: last.rpe,
                isWarmup: last.isWarmup,
                prescriptionNote: last.prescriptionNote,
                restDurationSeconds: seconds
            )
        )
    }

    private static func looksLikeJunkBeforeFirstSet(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return junkBeforeSetsPattern.firstMatch(in: line, range: range) != nil
    }

    private static func isSetLine(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return setLinePattern.firstMatch(in: line, range: range) != nil
    }

    private static func isRestLine(_ line: String) -> Bool {
        parseRestLine(line) != nil
    }

    private static func parseRestLine(_ line: String) -> Int? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = restLinePattern.firstMatch(in: line, range: range),
              let value = intCapture(1, in: line, match: match),
              let unit = stringCapture(2, in: line, match: match)?.lowercased()
        else { return nil }

        if unit.hasPrefix("m") {
            return value * 60
        }
        return value
    }

    private static func parseSetLine(_ line: String, fallbackSetIndex: Int) -> ParsedWorkoutSet? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = setLinePattern.firstMatch(in: line, range: range) else { return nil }

        let setIndex = intCapture(1, in: line, match: match) ?? fallbackSetIndex
        guard let weightValue = doubleCapture(2, in: line, match: match),
              let unit = stringCapture(3, in: line, match: match)?.lowercased(),
              let reps = intCapture(4, in: line, match: match)
        else { return nil }

        let weightKg: Double
        switch unit {
        case "kg":
            weightKg = weightValue
        case "lb":
            weightKg = weightValue * lbToKg
        default:
            return nil
        }

        let rpe = doubleCapture(5, in: line, match: match)
        let parenNote = stringCapture(6, in: line, match: match)?.trimmingCharacters(in: .whitespacesAndNewlines)

        var isWarmup = false
        var prescriptionNote: String?

        if let parenNote, !parenNote.isEmpty {
            let parenRange = NSRange(parenNote.startIndex..<parenNote.endIndex, in: parenNote)
            if warmupParenPattern.firstMatch(in: parenNote, range: parenRange) != nil {
                isWarmup = true
            } else {
                prescriptionNote = parenNote
            }
        }

        return ParsedWorkoutSet(
            setIndex: setIndex,
            weightKg: weightKg,
            reps: reps,
            rpe: rpe,
            isWarmup: isWarmup,
            prescriptionNote: prescriptionNote,
            restDurationSeconds: nil
        )
    }

    private static func stringCapture(_ group: Int, in line: String, match: NSTextCheckingResult) -> String? {
        guard match.range(at: group).location != NSNotFound,
              let range = Range(match.range(at: group), in: line)
        else { return nil }
        return String(line[range])
    }

    private static func intCapture(_ group: Int, in line: String, match: NSTextCheckingResult) -> Int? {
        guard let text = stringCapture(group, in: line, match: match) else { return nil }
        return Int(text)
    }

    private static func doubleCapture(_ group: Int, in line: String, match: NSTextCheckingResult) -> Double? {
        guard let text = stringCapture(group, in: line, match: match) else { return nil }
        return Double(text)
    }
}
