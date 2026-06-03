import Foundation

enum ReflectionRules {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func evaluate(snapshot: ReflectionSnapshot, calendar: Calendar) -> [InsightSpec] {
        var specs: [InsightSpec] = []
        specs.append(contentsOf: volumeRules(snapshot: snapshot, calendar: calendar))
        specs.append(contentsOf: acwrRules(snapshot: snapshot, referenceDate: snapshot.referenceDate))
        specs.append(contentsOf: e1RMPlateauRules(snapshot: snapshot, calendar: calendar))
        specs.append(
            contentsOf: hrvSuppressedRules(
                snapshot: snapshot,
                referenceDate: snapshot.referenceDate,
                calendar: calendar
            )
        )
        specs.append(
            contentsOf: sleepDeficitRules(
                snapshot: snapshot,
                referenceDate: snapshot.referenceDate,
                calendar: calendar
            )
        )
        specs.append(contentsOf: proteinGapRules(snapshot: snapshot, referenceDate: snapshot.referenceDate))
        if let weekly = weeklyProgressNote(snapshot: snapshot, calendar: calendar) {
            specs.append(weekly)
        }
        return specs
    }

    static func volumeRules(snapshot: ReflectionSnapshot, calendar: Calendar) -> [InsightSpec] {
        let isoWeek = snapshot.isoWeek
        var specs: [InsightSpec] = []
        for row in snapshot.volumeRows {
            let muscle = row.muscleGroup
            let sets = row.fractionalSets
            guard sets > 0 else { continue }
            let entity = muscle.rawValue
            let expiry = isoWeek.volumeExpiry(calendar: calendar, referenceDate: snapshot.referenceDate)

            if row.status == .belowMEV {
                let mev = row.mev
                let body = String(
                    format: "%@ volume is %.1f sets this week (minimum effective: %d).",
                    locale: posix,
                    muscle.insightDisplayName,
                    sets,
                    mev
                )
                specs.append(
                    InsightSpec(
                        dedupeKey: isoWeek.dedupeKey(type: .volumeBelowMEV, entity: entity),
                        type: .volumeBelowMEV,
                        severity: .warning,
                        bodyText: body,
                        relatedEntity: muscle.insightDisplayName,
                        expiresAt: expiry
                    )
                )
            }

            if row.status == .aboveMRV {
                let intSets = Int(sets.rounded())
                let excess = max(0, intSets - row.mrv)
                let body = String(
                    format: "%@ volume (%d sets) exceeds max recoverable. Cut %d sets next session.",
                    locale: posix,
                    muscle.insightDisplayName,
                    intSets,
                    excess
                )
                specs.append(
                    InsightSpec(
                        dedupeKey: isoWeek.dedupeKey(type: .volumeAboveMRV, entity: entity),
                        type: .volumeAboveMRV,
                        severity: .alert,
                        bodyText: body,
                        relatedEntity: muscle.insightDisplayName,
                        expiresAt: expiry
                    )
                )
            }
        }
        return specs
    }

    static func acwrRules(snapshot: ReflectionSnapshot, referenceDate: Date) -> [InsightSpec] {
        guard let acwr = snapshot.acwr else { return [] }
        let isoWeek = snapshot.isoWeek
        let entity = "total"
        let valueText = String(format: "%.2f", locale: posix, acwr.acwr)

        switch acwr.zone {
        case .overreach:
            let body =
                "Training load (ACWR \(valueText)) is well above your 4-week average. A rest day or reduced session is warranted."
            return [
                InsightSpec(
                    dedupeKey: isoWeek.dedupeKey(type: .acwrOverreach, entity: entity),
                    type: .acwrOverreach,
                    severity: .alert,
                    bodyText: body,
                    relatedEntity: "Training load",
                    expiresAt: referenceDate.addingTimeInterval(3 * 24 * 3600)
                ),
            ]
        case .belowOptimal:
            let body =
                "Training load (ACWR \(valueText)) is below your optimal zone. Consistent sessions rebuild momentum."
            return [
                InsightSpec(
                    dedupeKey: isoWeek.dedupeKey(type: .acwrUnderloading, entity: entity),
                    type: .acwrUnderloading,
                    severity: .warning,
                    bodyText: body,
                    relatedEntity: "Training load",
                    expiresAt: referenceDate.addingTimeInterval(5 * 24 * 3600)
                ),
            ]
        case .optimal, .caution:
            return []
        }
    }

    static func e1RMPlateauRules(snapshot: ReflectionSnapshot, calendar: Calendar) -> [InsightSpec] {
        let ref = calendar.startOfDay(for: snapshot.referenceDate)
        guard let windowStart = calendar.date(byAdding: .day, value: -27, to: ref) else { return [] }

        var byExercise: [String: [ExerciseProgressSample]] = [:]
        for row in snapshot.exerciseProgress {
            guard row.sessionDate >= windowStart, row.sessionDate <= ref else { continue }
            byExercise[row.exerciseID, default: []].append(row)
        }

        var specs: [InsightSpec] = []
        for (exerciseID, rows) in byExercise {
            let sessionDays = Set(rows.map { calendar.startOfDay(for: $0.sessionDate) })
            guard sessionDays.count >= 4 else { continue }
            let bestValues = rows.map(\.e1RMKg)
            guard let minBest = bestValues.min(), let maxBest = bestValues.max(), minBest > 0 else { continue }
            let changePct = ((maxBest - minBest) / minBest) * 100
            guard changePct < 2 else { continue }

            let displayName = rows.first?.displayName ?? exerciseID
            let best = maxBest
            let body = String(
                format: "%@ e1RM (%.1f kg) has been flat for 4 weeks. Consider a deload week or rep-range shift.",
                locale: posix,
                displayName,
                best
            )
            let entity = exerciseID
            specs.append(
                InsightSpec(
                    dedupeKey: snapshot.isoWeek.dedupeKey(type: .e1RMPlateau, entity: entity),
                    type: .e1RMPlateau,
                    severity: .info,
                    bodyText: body,
                    relatedEntity: displayName,
                    expiresAt: snapshot.referenceDate.addingTimeInterval(7 * 24 * 3600)
                )
            )
        }
        return specs
    }

    static func hrvSuppressedRules(
        snapshot: ReflectionSnapshot,
        referenceDate: Date,
        calendar: Calendar
    ) -> [InsightSpec] {
        let metrics = snapshot.dailyMetrics.filter { $0.hrvSDNN_ms != nil }
        guard metrics.count >= 4 else { return [] }

        let baselineValues = metrics.suffix(30).compactMap(\.hrvSDNN_ms)
        guard !baselineValues.isEmpty else { return [] }
        let mean = baselineValues.reduce(0, +) / Double(baselineValues.count)

        let consecutive = trailingConsecutiveDays(
            metrics: metrics,
            calendar: calendar,
            referenceDate: referenceDate,
            maxLookback: 10,
            predicate: { ($0.hrvSDNN_ms ?? .infinity) < mean }
        )
        guard consecutive.count >= 3 else { return [] }

        let body =
            "HRV has been below your baseline for \(consecutive.count) days. Prioritise sleep and keep intensity moderate."
        return [
            InsightSpec(
                dedupeKey: "hrvSuppressed.baseline.\(snapshot.isoWeek.keySegment)",
                type: .hrvSuppressed,
                severity: .warning,
                bodyText: body,
                relatedEntity: "HRV",
                expiresAt: referenceDate.addingTimeInterval(3 * 24 * 3600)
            ),
        ]
    }

    static func sleepDeficitRules(
        snapshot: ReflectionSnapshot,
        referenceDate: Date,
        calendar: Calendar
    ) -> [InsightSpec] {
        let metrics = snapshot.dailyMetrics.filter { $0.sleepHours != nil }
        guard !metrics.isEmpty else { return [] }

        let consecutive = trailingConsecutiveDays(
            metrics: metrics,
            calendar: calendar,
            referenceDate: referenceDate,
            maxLookback: 10,
            predicate: { ($0.sleepHours ?? 10) < 6.5 }
        )
        guard consecutive.count >= 3 else { return [] }

        let hours = consecutive.compactMap(\.sleepHours)
        let avg = hours.reduce(0, +) / Double(hours.count)
        let body = String(
            format: "Sleep has averaged %.1fh over the past %d nights. Recovery is likely reduced.",
            locale: posix,
            avg,
            consecutive.count
        )
        return [
            InsightSpec(
                dedupeKey: "sleepDeficit.\(snapshot.isoWeek.keySegment)",
                type: .sleepDeficit,
                severity: .warning,
                bodyText: body,
                relatedEntity: "Sleep",
                expiresAt: referenceDate.addingTimeInterval(2 * 24 * 3600)
            ),
        ]
    }

    static func proteinGapRules(snapshot: ReflectionSnapshot, referenceDate: Date) -> [InsightSpec] {
        guard let targetMin = snapshot.proteinTargetMinGrams else { return [] }
        let withData = snapshot.proteinSamples
            .filter { $0.proteinG != nil }
            .sorted { $0.date > $1.date }
            .prefix(7)
        guard withData.count >= 3 else { return [] }

        let belowTarget = withData.filter { ($0.proteinG ?? 0) < targetMin }
        guard belowTarget.count >= 3 else { return [] }

        let grams = withData.compactMap(\.proteinG)
        let avg = grams.reduce(0, +) / Double(grams.count)
        let body = String(
            format: "Protein has averaged %.0fg on tracked days vs your %.0fg minimum.",
            locale: posix,
            avg,
            targetMin
        )
        return [
            InsightSpec(
                dedupeKey: "proteinGap.\(snapshot.isoWeek.keySegment)",
                type: .proteinGap,
                severity: .warning,
                bodyText: body,
                relatedEntity: "Nutrition",
                expiresAt: referenceDate.addingTimeInterval(3 * 24 * 3600)
            ),
        ]
    }

    static func weeklyProgressNote(snapshot: ReflectionSnapshot, calendar: Calendar) -> InsightSpec? {
        let inputs = snapshot.weeklyProgress
        var parts: [String] = []

        if inputs.sessionCount > 0 {
            parts.append("\(inputs.sessionCount) session\(inputs.sessionCount == 1 ? "" : "s") logged.")
        } else {
            parts.append("No sessions logged this week yet.")
        }

        if !inputs.musclesCovered.isEmpty {
            let names = inputs.musclesCovered.map(\.insightDisplayName)
            let list = formattedList(names)
            parts.append("\(list) covered.")
        }

        if let pr = inputs.topPR {
            parts.append(
                String(
                    format: "New %@ e1RM (%.0f kg).",
                    locale: posix,
                    pr.name,
                    pr.e1RMKg
                )
            )
        }

        if let zone = inputs.acwrZone {
            parts.append(acwrZonePhrase(zone))
        }

        if let sleep = inputs.averageSleepHours {
            parts.append(
                String(format: "Sleep averaged %.1f h.", locale: posix, sleep)
            )
        }

        let body = parts.joined(separator: " ")
        return InsightSpec(
            dedupeKey: "weeklyProgressNote.\(snapshot.isoWeek.keySegment)",
            type: .weeklyProgressNote,
            severity: .info,
            bodyText: body,
            relatedEntity: nil,
            expiresAt: snapshot.referenceDate.addingTimeInterval(8 * 24 * 3600)
        )
    }

    private static func acwrZonePhrase(_ zone: ACWRZone) -> String {
        switch zone {
        case .optimal:
            return "Load in optimal zone."
        case .belowOptimal:
            return "Load below optimal zone."
        case .caution:
            return "Load in caution zone."
        case .overreach:
            return "Load in overreach zone."
        }
    }

    private static func formattedList(_ items: [String]) -> String {
        switch items.count {
        case 0:
            return ""
        case 1:
            return items[0]
        case 2:
            return "\(items[0]) and \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head), and \(items.last!)"
        }
    }

    static func trailingConsecutiveDays(
        metrics: [DailyMetricSample],
        calendar: Calendar,
        referenceDate: Date,
        maxLookback: Int,
        predicate: (DailyMetricSample) -> Bool
    ) -> [DailyMetricSample] {
        var byDay: [Date: DailyMetricSample] = [:]
        for metric in metrics {
            byDay[calendar.startOfDay(for: metric.date)] = metric
        }

        var run: [DailyMetricSample] = []
        var day = calendar.startOfDay(for: referenceDate)
        for _ in 0..<maxLookback {
            guard let sample = byDay[day], predicate(sample) else { break }
            run.insert(sample, at: 0)
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return run
    }
}
