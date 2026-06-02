import Foundation
import SwiftData

enum RetrievalUATVerdict: String, Sendable, Equatable {
    case pass = "PASS"
    case fail = "FAIL"
    case review = "REVIEW"
    case limit = "LIMIT"
}

struct RetrievalUATHitDisplay: Identifiable, Sendable, Equatable {
    let dayKey: String
    let score: Float
    let snippet: String

    var id: String { dayKey }

    var formattedScore: String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), score)
    }
}

struct RetrievalUATResult: Identifiable, Sendable, Equatable {
    let definitionID: String
    let label: String
    let query: String
    let verdict: RetrievalUATVerdict
    let expectedMode: RetrievalUATExpectedMode
    let detectedModeLabel: String
    let modeMatched: Bool
    let checkLabel: String
    let ratioLabel: String
    let hits: [RetrievalUATHitDisplay]
    let structuredAnswer: String?
    let errorMessage: String?

    var id: String { definitionID }
}

struct RetrievalUATCorpusStats: Sendable, Equatable {
    let dayCount: Int
    let earliestDayKey: String
    let latestDayKey: String
    let vectorCount: Int
}

struct RetrievalUATDayIndexes {
    let metricsByDayKey: [String: DailyMetric]
    let nutritionByDayKey: [String: DailyNutrition]
    let workoutDayKeys: Set<String>
    let legExerciseDayKeys: Set<String>
    let runningWorkoutDayKeys: Set<String>
    let proteinMedian: Double?
    let sleep30DayMean: Double?
    let hrv30DayMean: Double?
    let latestBodyMassDayKey: String?
    let heaviestSquatAnswer: String?
    let hasWorkoutInLast14Days: Bool
    let todayHasHRV: Bool
    let calendar: Calendar
    let referenceDate: Date

    static func load(
        in context: ModelContext,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) throws -> RetrievalUATDayIndexes {
        let metrics = try context.fetch(FetchDescriptor<DailyMetric>())
        var metricsByDayKey: [String: DailyMetric] = [:]
        for metric in metrics {
            let key = Summarizer.dayKey(for: metric.date, calendar: calendar)
            metricsByDayKey[key] = metric
        }

        let nutritionRows = try context.fetch(FetchDescriptor<DailyNutrition>())
        var nutritionByDayKey: [String: DailyNutrition] = [:]
        for row in nutritionRows {
            let key = Summarizer.dayKey(for: row.date, calendar: calendar)
            nutritionByDayKey[key] = row
        }

        var workoutDayKeys: Set<String> = []
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        for session in sessions {
            workoutDayKeys.insert(Summarizer.dayKey(for: session.date, calendar: calendar))
        }

        var legExerciseDayKeys: Set<String> = []
        let exercises = try context.fetch(FetchDescriptor<WorkoutExercise>())
        for exercise in exercises {
            guard RetrievalUATGrader.matchesLegKeyword(exercise.exerciseTitle) else { continue }
            guard let session = exercise.session else { continue }
            legExerciseDayKeys.insert(Summarizer.dayKey(for: session.date, calendar: calendar))
        }

        var runningWorkoutDayKeys: Set<String> = []
        let appleWorkouts = try context.fetch(FetchDescriptor<AppleWorkout>())
        for workout in appleWorkouts {
            let key = Summarizer.dayKey(for: workout.startDate, calendar: calendar)
            workoutDayKeys.insert(key)
            if AppleWorkoutMapper.isRunningActivity(workout.activityType) {
                runningWorkoutDayKeys.insert(key)
            }
        }

        let proteinMedian = median(of: nutritionRows.compactMap(\.proteinG))
        let sleep30Floor = calendar.date(byAdding: .day, value: -30, to: referenceDate) ?? referenceDate
        let recentMetrics = metrics.filter { $0.date >= sleep30Floor }
        let sleep30DayMean = mean(of: recentMetrics.compactMap(\.sleepHours))
        let hrv30DayMean = mean(of: recentMetrics.compactMap(\.hrvSDNN_ms))

        var latestBodyMassDayKey: String?
        for (dayKey, metric) in metricsByDayKey {
            guard let mass = metric.bodyMassKg, mass > 0 else { continue }
            if latestBodyMassDayKey == nil || dayKey > latestBodyMassDayKey! {
                latestBodyMassDayKey = dayKey
            }
        }

        let heaviestSquatAnswer = Self.computeHeaviestSquat(
            sets: try context.fetch(FetchDescriptor<SetEntry>()),
            calendar: calendar
        )

        let floor14 = TemporalQueryParser.dayKeyOnOrAfter(
            daysBack: 14,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let hasWorkoutInLast14Days = workoutDayKeys.contains { $0 >= floor14 }

        let todayKey = Summarizer.dayKey(for: referenceDate, calendar: calendar)
        let todayHasHRV: Bool = {
            guard let hrv = metricsByDayKey[todayKey]?.hrvSDNN_ms else { return false }
            return hrv > 0
        }()

        return RetrievalUATDayIndexes(
            metricsByDayKey: metricsByDayKey,
            nutritionByDayKey: nutritionByDayKey,
            workoutDayKeys: workoutDayKeys,
            legExerciseDayKeys: legExerciseDayKeys,
            runningWorkoutDayKeys: runningWorkoutDayKeys,
            proteinMedian: proteinMedian,
            sleep30DayMean: sleep30DayMean,
            hrv30DayMean: hrv30DayMean,
            latestBodyMassDayKey: latestBodyMassDayKey,
            heaviestSquatAnswer: heaviestSquatAnswer,
            hasWorkoutInLast14Days: hasWorkoutInLast14Days,
            todayHasHRV: todayHasHRV,
            calendar: calendar,
            referenceDate: referenceDate
        )
    }

    private static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func mean(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func computeHeaviestSquat(
        sets: [SetEntry],
        calendar: Calendar
    ) -> String? {
        var bestWeight: Double?
        var bestDayKey: String?
        var bestTitle: String?

        for set in sets {
            guard let weight = set.weightKg, weight > 0,
                  let exercise = set.exercise,
                  exercise.exerciseTitle.lowercased().contains("squat"),
                  let session = exercise.session
            else { continue }
            let dayKey = Summarizer.dayKey(for: session.date, calendar: calendar)
            if bestWeight == nil || weight > bestWeight! {
                bestWeight = weight
                bestDayKey = dayKey
                bestTitle = exercise.exerciseTitle
            }
        }

        guard let weight = bestWeight, let dayKey = bestDayKey, let title = bestTitle else {
            return "none (no squat sets in store)"
        }
        return String(
            format: "%.1f kg on %@ (%@)",
            locale: Locale(identifier: "en_US_POSIX"),
            weight,
            dayKey,
            title
        )
    }
}

enum RetrievalUATGrader {
    private static let legKeywords = [
        "squat",
        "leg press",
        "lunge",
        "leg curl",
        "leg extension",
        "rdl",
        "hamstring",
        "quad",
        "calf",
    ]

    static func corpusStats(modelContainer: ModelContainer) throws -> RetrievalUATCorpusStats {
        let context = ModelContext(modelContainer)
        let vectorCount = try context.fetchCount(FetchDescriptor<HealthVector>())
        let vectors = try context.fetch(
            FetchDescriptor<HealthVector>(sortBy: [SortDescriptor(\.dayKey, order: .forward)])
        )
        let dayKeys = Set(vectors.map(\.dayKey))
        guard let first = vectors.first, let last = vectors.last else {
            return RetrievalUATCorpusStats(
                dayCount: dayKeys.count,
                earliestDayKey: "none",
                latestDayKey: "none",
                vectorCount: vectorCount
            )
        }
        return RetrievalUATCorpusStats(
            dayCount: dayKeys.count,
            earliestDayKey: first.dayKey,
            latestDayKey: last.dayKey,
            vectorCount: vectorCount
        )
    }

    static func grade(
        definition: RetrievalUATDefinition,
        run: DiagnosticsRetrievalRun,
        indexes: RetrievalUATDayIndexes,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> RetrievalUATResult {
        let detectedModeLabel = run.mode.uatModeLabel
        let modeMatched = definition.expectedMode.matches(run.mode)
        let hits = run.hits.map {
            RetrievalUATHitDisplay(
                dayKey: $0.dayKey,
                score: $0.score,
                snippet: shortSnippet($0.summaryText, maxLength: 96)
            )
        }
        let parsedWindow = TemporalQueryParser.window(
            in: definition.query,
            referenceDate: referenceDate,
            calendar: calendar
        )

        if let error = run.errorMessage {
            return baseResult(
                definition: definition,
                verdict: .fail,
                detectedModeLabel: detectedModeLabel,
                modeMatched: modeMatched,
                ratioLabel: "n/a",
                hits: hits,
                structuredAnswer: structuredAnswer(for: definition.gradeRule, indexes: indexes),
                errorMessage: error
            )
        }

        if run.fallbackToGlobal {
            return baseResult(
                definition: definition,
                verdict: .fail,
                detectedModeLabel: detectedModeLabel,
                modeMatched: modeMatched,
                ratioLabel: "n/a",
                hits: hits,
                structuredAnswer: structuredAnswer(for: definition.gradeRule, indexes: indexes),
                errorMessage: "Temporal window empty; global fallback"
            )
        }

        switch definition.gradeRule {
        case .allTop3InWindowAnd(let check):
            return gradeAllTop3(
                definition: definition,
                check: check,
                hits: hits,
                indexes: indexes,
                parsedWindow: parsedWindow,
                modeMatched: modeMatched,
                detectedModeLabel: detectedModeLabel,
                referenceDate: referenceDate,
                calendar: calendar
            )
        case .top1RecencyLegDay:
            return gradeTop1LegDay(
                definition: definition,
                hits: hits,
                indexes: indexes,
                modeMatched: modeMatched,
                detectedModeLabel: detectedModeLabel,
                referenceDate: referenceDate,
                calendar: calendar
            )
        case .top1RecencyRun:
            return gradeTop1Run(
                definition: definition,
                hits: hits,
                indexes: indexes,
                modeMatched: modeMatched,
                detectedModeLabel: detectedModeLabel,
                referenceDate: referenceDate,
                calendar: calendar
            )
        case .top1LatestBodyMass:
            return gradeTop1BodyMass(
                definition: definition,
                hits: hits,
                indexes: indexes,
                modeMatched: modeMatched,
                detectedModeLabel: detectedModeLabel
            )
        case .reviewHardLegDays:
            return gradeReviewHardLeg(
                definition: definition,
                hits: hits,
                indexes: indexes,
                modeMatched: modeMatched,
                detectedModeLabel: detectedModeLabel
            )
        case .majoritySleepBelowMean30d:
            return gradeMajority(
                definition: definition,
                hits: hits,
                indexes: indexes,
                check: .sleepBelowMean30d,
                parsedWindow: parsedWindow,
                modeMatched: modeMatched,
                detectedModeLabel: detectedModeLabel,
                referenceDate: referenceDate,
                calendar: calendar
            )
        case .majorityProteinAboveMedian:
            return gradeMajority(
                definition: definition,
                hits: hits,
                indexes: indexes,
                check: .proteinAboveMedian,
                parsedWindow: parsedWindow,
                modeMatched: modeMatched,
                detectedModeLabel: detectedModeLabel,
                referenceDate: referenceDate,
                calendar: calendar
            )
        case .reviewHRVBelowMean30d:
            return gradeReviewHRV(
                definition: definition,
                hits: hits,
                indexes: indexes,
                modeMatched: modeMatched,
                detectedModeLabel: detectedModeLabel,
                parsedWindow: parsedWindow,
                referenceDate: referenceDate,
                calendar: calendar
            )
        case .limitHeaviestSquat:
            return baseResult(
                definition: definition,
                verdict: .limit,
                detectedModeLabel: detectedModeLabel,
                modeMatched: modeMatched,
                ratioLabel: "n/a",
                hits: hits,
                structuredAnswer: indexes.heaviestSquatAnswer,
                errorMessage: nil
            )
        case .contextGymTonight:
            return gradeContextGym(
                definition: definition,
                hits: hits,
                indexes: indexes,
                modeMatched: modeMatched,
                detectedModeLabel: detectedModeLabel,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
    }

    static func matchesLegKeyword(_ title: String) -> Bool {
        let normalized = title.lowercased()
        return legKeywords.contains { normalized.contains($0) }
    }

    private static func gradeAllTop3(
        definition: RetrievalUATDefinition,
        check: RetrievalUATAutoCheck,
        hits: [RetrievalUATHitDisplay],
        indexes: RetrievalUATDayIndexes,
        parsedWindow: TemporalQueryWindow?,
        modeMatched: Bool,
        detectedModeLabel: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> RetrievalUATResult {
        let evaluated = Array(hits.prefix(3))
        var passCount = 0
        for hit in evaluated {
            if satisfies(
                check,
                dayKey: hit.dayKey,
                indexes: indexes,
                parsedWindow: parsedWindow,
                referenceDate: referenceDate,
                calendar: calendar
            ) {
                passCount += 1
            }
        }
        let count = evaluated.count
        let ratioLabel = count > 0 ? "\(passCount)/\(count)" : "0/0"
        let allPass = count > 0 && passCount == count
        let verdict: RetrievalUATVerdict = (modeMatched && allPass) ? .pass : .fail
        return baseResult(
            definition: definition,
            verdict: verdict,
            detectedModeLabel: detectedModeLabel,
            modeMatched: modeMatched,
            ratioLabel: ratioLabel,
            hits: hits,
            structuredAnswer: nil,
            errorMessage: count == 0 ? "No hits returned" : nil
        )
    }

    private static func gradeTop1LegDay(
        definition: RetrievalUATDefinition,
        hits: [RetrievalUATHitDisplay],
        indexes: RetrievalUATDayIndexes,
        modeMatched: Bool,
        detectedModeLabel: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> RetrievalUATResult {
        guard let top = hits.first else {
            return baseResult(
                definition: definition,
                verdict: .fail,
                detectedModeLabel: detectedModeLabel,
                modeMatched: modeMatched,
                ratioLabel: "0/1",
                hits: hits,
                structuredAnswer: nil,
                errorMessage: "No hits returned"
            )
        }
        let hasWorkout = satisfies(.hasWorkout, dayKey: top.dayKey, indexes: indexes, parsedWindow: nil, referenceDate: referenceDate, calendar: calendar)
        let recent = satisfies(.isRecent(days: 45), dayKey: top.dayKey, indexes: indexes, parsedWindow: nil, referenceDate: referenceDate, calendar: calendar)
        let leg = satisfies(.legKeyword, dayKey: top.dayKey, indexes: indexes, parsedWindow: nil, referenceDate: referenceDate, calendar: calendar)
        let passCount = [hasWorkout, recent, leg].filter { $0 }.count
        let ratioLabel = "\(passCount)/3"
        let verdict: RetrievalUATVerdict
        if modeMatched && hasWorkout && recent && leg {
            verdict = .pass
        } else if hasWorkout && recent && !leg {
            verdict = .review
        } else {
            verdict = .fail
        }
        return baseResult(
            definition: definition,
            verdict: verdict,
            detectedModeLabel: detectedModeLabel,
            modeMatched: modeMatched,
            ratioLabel: ratioLabel,
            hits: hits,
            structuredAnswer: nil,
            errorMessage: nil
        )
    }

    private static func gradeTop1Run(
        definition: RetrievalUATDefinition,
        hits: [RetrievalUATHitDisplay],
        indexes: RetrievalUATDayIndexes,
        modeMatched: Bool,
        detectedModeLabel: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> RetrievalUATResult {
        guard let top = hits.first else {
            return baseResult(
                definition: definition,
                verdict: .fail,
                detectedModeLabel: detectedModeLabel,
                modeMatched: modeMatched,
                ratioLabel: "0/1",
                hits: hits,
                structuredAnswer: nil,
                errorMessage: "No hits returned"
            )
        }
        let running = satisfies(.isRunning, dayKey: top.dayKey, indexes: indexes, parsedWindow: nil, referenceDate: referenceDate, calendar: calendar)
        let recent = satisfies(.isRecent(days: 60), dayKey: top.dayKey, indexes: indexes, parsedWindow: nil, referenceDate: referenceDate, calendar: calendar)
        let passCount = [running, recent].filter { $0 }.count
        let verdict: RetrievalUATVerdict = (modeMatched && running && recent) ? .pass : .fail
        return baseResult(
            definition: definition,
            verdict: verdict,
            detectedModeLabel: detectedModeLabel,
            modeMatched: modeMatched,
            ratioLabel: "\(passCount)/2",
            hits: hits,
            structuredAnswer: nil,
            errorMessage: nil
        )
    }

    private static func gradeTop1BodyMass(
        definition: RetrievalUATDefinition,
        hits: [RetrievalUATHitDisplay],
        indexes: RetrievalUATDayIndexes,
        modeMatched: Bool,
        detectedModeLabel: String
    ) -> RetrievalUATResult {
        let structured = indexes.latestBodyMassDayKey.map { dayKey in
            let mass = indexes.metricsByDayKey[dayKey]?.bodyMassKg
            let massText = mass.map { String(format: "%.1f kg", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "?"
            return "\(massText) on \(dayKey)"
        } ?? "none (no body mass in store)"

        guard let top = hits.first, let latestKey = indexes.latestBodyMassDayKey else {
            return baseResult(
                definition: definition,
                verdict: .fail,
                detectedModeLabel: detectedModeLabel,
                modeMatched: modeMatched,
                ratioLabel: "0/1",
                hits: hits,
                structuredAnswer: structured,
                errorMessage: hits.isEmpty ? "No hits returned" : "No body mass in store"
            )
        }
        let hasMass = satisfies(.hasBodyMass, dayKey: top.dayKey, indexes: indexes, parsedWindow: nil, referenceDate: indexes.referenceDate, calendar: indexes.calendar)
        let isLatest = top.dayKey == latestKey
        let passCount = [hasMass, isLatest].filter { $0 }.count
        let verdict: RetrievalUATVerdict = (modeMatched && hasMass && isLatest) ? .pass : .fail
        return baseResult(
            definition: definition,
            verdict: verdict,
            detectedModeLabel: detectedModeLabel,
            modeMatched: modeMatched,
            ratioLabel: "\(passCount)/2",
            hits: hits,
            structuredAnswer: structured,
            errorMessage: nil
        )
    }

    private static func gradeReviewHardLeg(
        definition: RetrievalUATDefinition,
        hits: [RetrievalUATHitDisplay],
        indexes: RetrievalUATDayIndexes,
        modeMatched: Bool,
        detectedModeLabel: String
    ) -> RetrievalUATResult {
        let evaluated = Array(hits.prefix(3))
        let workoutCount = evaluated.filter {
            indexes.workoutDayKeys.contains($0.dayKey)
        }.count
        let legCount = evaluated.filter {
            indexes.legExerciseDayKeys.contains($0.dayKey)
        }.count
        let count = evaluated.count
        let ratioLabel = count > 0
            ? "hasWorkout \(workoutCount)/\(count) legKeyword \(legCount)/\(count)"
            : "hasWorkout 0/0 legKeyword 0/0"
        return baseResult(
            definition: definition,
            verdict: .review,
            detectedModeLabel: detectedModeLabel,
            modeMatched: modeMatched,
            ratioLabel: ratioLabel,
            hits: hits,
            structuredAnswer: nil,
            errorMessage: nil
        )
    }

    private static func gradeMajority(
        definition: RetrievalUATDefinition,
        hits: [RetrievalUATHitDisplay],
        indexes: RetrievalUATDayIndexes,
        check: RetrievalUATAutoCheck,
        parsedWindow: TemporalQueryWindow?,
        modeMatched: Bool,
        detectedModeLabel: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> RetrievalUATResult {
        let evaluated = Array(hits.prefix(3))
        var passCount = 0
        for hit in evaluated {
            if satisfies(check, dayKey: hit.dayKey, indexes: indexes, parsedWindow: parsedWindow, referenceDate: referenceDate, calendar: calendar) {
                passCount += 1
            }
        }
        let count = evaluated.count
        let ratioLabel = count > 0 ? "\(passCount)/\(count)" : "0/0"
        let majority = count > 0 && passCount > count / 2
        let verdict: RetrievalUATVerdict = majority ? .pass : .review
        return baseResult(
            definition: definition,
            verdict: verdict,
            detectedModeLabel: detectedModeLabel,
            modeMatched: modeMatched,
            ratioLabel: ratioLabel,
            hits: hits,
            structuredAnswer: nil,
            errorMessage: count == 0 ? "No hits returned" : nil
        )
    }

    private static func gradeReviewHRV(
        definition: RetrievalUATDefinition,
        hits: [RetrievalUATHitDisplay],
        indexes: RetrievalUATDayIndexes,
        modeMatched: Bool,
        detectedModeLabel: String,
        parsedWindow: TemporalQueryWindow?,
        referenceDate: Date,
        calendar: Calendar
    ) -> RetrievalUATResult {
        let evaluated = Array(hits.prefix(3))
        var passCount = 0
        for hit in evaluated {
            if satisfies(.hrvBelowMean30d, dayKey: hit.dayKey, indexes: indexes, parsedWindow: parsedWindow, referenceDate: referenceDate, calendar: calendar) {
                passCount += 1
            }
        }
        let count = evaluated.count
        let ratioLabel = count > 0 ? "hrvBelowMean(30d) \(passCount)/\(count)" : "hrvBelowMean(30d) 0/0"
        return baseResult(
            definition: definition,
            verdict: .review,
            detectedModeLabel: detectedModeLabel,
            modeMatched: modeMatched,
            ratioLabel: ratioLabel,
            hits: hits,
            structuredAnswer: nil,
            errorMessage: nil
        )
    }

    private static func gradeContextGym(
        definition: RetrievalUATDefinition,
        hits: [RetrievalUATHitDisplay],
        indexes: RetrievalUATDayIndexes,
        modeMatched: Bool,
        detectedModeLabel: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> RetrievalUATResult {
        let floor14 = TemporalQueryParser.dayKeyOnOrAfter(
            daysBack: 14,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let workoutHits = hits.prefix(3).filter {
            $0.dayKey >= floor14 && indexes.workoutDayKeys.contains($0.dayKey)
        }.count
        let contextOK = workoutHits >= 1 && indexes.todayHasHRV
        let ratioLabel = "workoutHits14d \(workoutHits)/\(min(hits.count, 3)) todayHRV \(indexes.todayHasHRV ? "y" : "n")"
        let verdict: RetrievalUATVerdict = contextOK ? .pass : .fail
        return baseResult(
            definition: definition,
            verdict: verdict,
            detectedModeLabel: detectedModeLabel,
            modeMatched: modeMatched,
            ratioLabel: ratioLabel,
            hits: hits,
            structuredAnswer: nil,
            errorMessage: nil
        )
    }

    private static func baseResult(
        definition: RetrievalUATDefinition,
        verdict: RetrievalUATVerdict,
        detectedModeLabel: String,
        modeMatched: Bool,
        ratioLabel: String,
        hits: [RetrievalUATHitDisplay],
        structuredAnswer: String?,
        errorMessage: String?
    ) -> RetrievalUATResult {
        RetrievalUATResult(
            definitionID: definition.id,
            label: definition.label,
            query: definition.query,
            verdict: verdict,
            expectedMode: definition.expectedMode,
            detectedModeLabel: detectedModeLabel,
            modeMatched: modeMatched,
            checkLabel: definition.checkLabel,
            ratioLabel: ratioLabel,
            hits: hits,
            structuredAnswer: structuredAnswer,
            errorMessage: errorMessage
        )
    }

    private static func structuredAnswer(
        for rule: RetrievalUATGradeRule,
        indexes: RetrievalUATDayIndexes
    ) -> String? {
        switch rule {
        case .top1LatestBodyMass:
            return indexes.latestBodyMassDayKey.map { key in
                let mass = indexes.metricsByDayKey[key]?.bodyMassKg
                let massText = mass.map { String(format: "%.1f kg", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "?"
                return "\(massText) on \(key)"
            }
        case .limitHeaviestSquat:
            return indexes.heaviestSquatAnswer
        default:
            return nil
        }
    }

    private static func satisfies(
        _ check: RetrievalUATAutoCheck,
        dayKey: String,
        indexes: RetrievalUATDayIndexes,
        parsedWindow: TemporalQueryWindow?,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        switch check {
        case .composite(let parts):
            return parts.allSatisfy {
                satisfies($0, dayKey: dayKey, indexes: indexes, parsedWindow: parsedWindow, referenceDate: referenceDate, calendar: calendar)
            }
        case .inParsedWindow:
            guard let window = parsedWindow else { return true }
            return window.contains(dayKey: dayKey)
        case .hasSleep:
            guard let hours = indexes.metricsByDayKey[dayKey]?.sleepHours else { return false }
            return hours > 0
        case .hasWorkout:
            return indexes.workoutDayKeys.contains(dayKey)
        case .hasNutrition:
            return indexes.nutritionByDayKey[dayKey] != nil
        case .isRecent(let days):
            let floor = TemporalQueryParser.dayKeyOnOrAfter(
                daysBack: days,
                referenceDate: referenceDate,
                calendar: calendar
            )
            return dayKey >= floor
        case .proteinAboveMedian:
            guard let median = indexes.proteinMedian,
                  let protein = indexes.nutritionByDayKey[dayKey]?.proteinG
            else { return false }
            return protein > median
        case .sleepBelowMean30d:
            guard let mean = indexes.sleep30DayMean,
                  let sleep = indexes.metricsByDayKey[dayKey]?.sleepHours
            else { return false }
            return sleep < mean
        case .isRunning:
            return indexes.runningWorkoutDayKeys.contains(dayKey)
        case .hasBodyMass:
            guard let mass = indexes.metricsByDayKey[dayKey]?.bodyMassKg else { return false }
            return mass > 0
        case .legKeyword:
            return indexes.legExerciseDayKeys.contains(dayKey)
        case .hrvBelowMean30d:
            guard let mean = indexes.hrv30DayMean,
                  let hrv = indexes.metricsByDayKey[dayKey]?.hrvSDNN_ms
            else { return false }
            return hrv < mean
        }
    }

    private static func shortSnippet(_ text: String, maxLength: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= maxLength { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<end]) + "..."
    }
}
