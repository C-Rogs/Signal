import SwiftData
import XCTest
@testable import Signal

@MainActor
final class ReflectionEngineTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var calendar: Calendar!
    private var referenceDate: Date!

    override func setUpWithError() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = cal
        referenceDate = cal.date(from: DateComponents(year: 2026, month: 6, day: 3))!

        container = try ModelContainer(
            for: SignalModelContainer.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    func testVolumeBelowMEVFiresAndDedupesSameWeek() async throws {
        try insertQuadSession(sets: 1)
        await ReflectionEngine.shared.runReflection(in: context, referenceDate: referenceDate)
        let first = try fetchInsights(type: .volumeBelowMEV)
        XCTAssertEqual(first.count, 1)

        await ReflectionEngine.shared.runReflection(in: context, referenceDate: referenceDate)
        let second = try fetchInsights(type: .volumeBelowMEV)
        XCTAssertEqual(second.count, 1)
    }

    func testVolumeAboveMRVFiresWithExpiry() async throws {
        try insertQuadSession(sets: 30)
        await ReflectionEngine.shared.runReflection(in: context, referenceDate: referenceDate)
        let rows = try fetchInsights(type: .volumeAboveMRV)
        XCTAssertEqual(rows.count, 1)
        XCTAssertNotNil(rows.first?.expiresAt)
        XCTAssertGreaterThan(rows.first!.expiresAt!, referenceDate)
    }

    func testAcwrOverreachFiresAt160NotAt129() {
        let isoWeek = ISOWeekIdentifier.current(calendar: calendar, referenceDate: referenceDate)
        let overreach = ACWRResult(acuteLoad: 16, chronicLoad: 10, acwr: 1.6, zone: .overreach)
        let optimal = ACWRResult(acuteLoad: 12.9, chronicLoad: 10, acwr: 1.29, zone: .optimal)

        let overSpecs = ReflectionRules.acwrRules(
            snapshot: minimalSnapshot(acwr: overreach, isoWeek: isoWeek),
            referenceDate: referenceDate
        )
        XCTAssertEqual(overSpecs.count, 1)
        XCTAssertEqual(overSpecs.first?.type, .acwrOverreach)

        let optimalSpecs = ReflectionRules.acwrRules(
            snapshot: minimalSnapshot(acwr: optimal, isoWeek: isoWeek),
            referenceDate: referenceDate
        )
        XCTAssertTrue(optimalSpecs.isEmpty)
    }

    func testAcwrOverreachExpiresWhenReturningToOptimal() async throws {
        let isoWeek = ISOWeekIdentifier.current(calendar: calendar, referenceDate: referenceDate)
        let key = isoWeek.dedupeKey(type: .acwrOverreach, entity: "total")
        let insight = Insight(
            dedupeKey: key,
            type: .acwrOverreach,
            severity: .alert,
            bodyText: "stale",
            expiresAt: referenceDate.addingTimeInterval(86_400),
            isActioned: false
        )
        context.insert(insight)
        try context.save()

        try insertBalancedACWRSessions()
        await ReflectionEngine.shared.runReflection(in: context, referenceDate: referenceDate)

        let row = try fetchInsight(dedupeKey: key)
        XCTAssertNotNil(row?.expiresAt)
        XCTAssertLessThanOrEqual(row!.expiresAt!, referenceDate)
    }

    func testHrvSuppressedRequiresThreeConsecutiveDays() {
        let ref = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
        let isoWeek = ISOWeekIdentifier.current(calendar: calendar, referenceDate: ref)
        let days = (0..<25).compactMap { offset -> DailyMetricSample? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: ref) else { return nil }
            let value: Double = offset < 10 ? 28 : 55
            return DailyMetricSample(date: date, hrvSDNN_ms: value, sleepHours: nil)
        }
        let consecutive = ReflectionRules.hrvSuppressedRules(
            snapshot: minimalSnapshot(metrics: days, isoWeek: isoWeek, referenceDate: ref),
            referenceDate: ref,
            calendar: calendar
        )
        XCTAssertEqual(consecutive.count, 1)

        let blockedDays = (0..<25).compactMap { offset -> DailyMetricSample? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: ref) else { return nil }
            let value: Double = offset < 2 ? 28 : 55
            return DailyMetricSample(date: date, hrvSDNN_ms: value, sleepHours: nil)
        }
        let blocked = ReflectionRules.hrvSuppressedRules(
            snapshot: minimalSnapshot(metrics: blockedDays, isoWeek: isoWeek, referenceDate: ref),
            referenceDate: ref,
            calendar: calendar
        )
        XCTAssertTrue(blocked.isEmpty)
    }

    func testSleepDeficitRequiresThreeConsecutiveNights() {
        let isoWeek = ISOWeekIdentifier.current(calendar: calendar, referenceDate: referenceDate)
        let ref = referenceDate!
        let lowSleep = (0..<3).compactMap { offset -> DailyMetricSample? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: ref) else { return nil }
            return DailyMetricSample(date: date, hrvSDNN_ms: nil, sleepHours: 5.5)
        }
        let fires = ReflectionRules.sleepDeficitRules(
            snapshot: minimalSnapshot(metrics: lowSleep, isoWeek: isoWeek),
            referenceDate: ref,
            calendar: calendar
        )
        XCTAssertEqual(fires.count, 1)

        var withGap = lowSleep
        withGap[2] = DailyMetricSample(
            date: calendar.date(byAdding: .day, value: -2, to: ref)!,
            hrvSDNN_ms: nil,
            sleepHours: 8
        )
        let blocked = ReflectionRules.sleepDeficitRules(
            snapshot: minimalSnapshot(metrics: withGap, isoWeek: isoWeek),
            referenceDate: ref,
            calendar: calendar
        )
        XCTAssertTrue(blocked.isEmpty)
    }

    func testWeeklyProgressNoteCreatedOncePerWeek() async throws {
        await ReflectionEngine.shared.runReflection(in: context, referenceDate: referenceDate)
        let first = try fetchInsights(type: .weeklyProgressNote)
        XCTAssertEqual(first.count, 1)

        await ReflectionEngine.shared.runReflection(in: context, referenceDate: referenceDate)
        let second = try fetchInsights(type: .weeklyProgressNote)
        XCTAssertEqual(second.count, 1)
    }

    func testExpiredInsightIgnoredForDedupAllowsReactivation() async throws {
        let isoWeek = ISOWeekIdentifier.current(calendar: calendar, referenceDate: referenceDate)
        let key = isoWeek.dedupeKey(type: .volumeBelowMEV, entity: MuscleGroup.quads.rawValue)
        let expired = Insight(
            dedupeKey: key,
            type: .volumeBelowMEV,
            severity: .warning,
            bodyText: "old",
            expiresAt: referenceDate.addingTimeInterval(-86_400),
            isActioned: false
        )
        context.insert(expired)
        try insertQuadSession(sets: 1)
        try context.save()

        await ReflectionEngine.shared.runReflection(in: context, referenceDate: referenceDate)
        let rows = try fetchInsight(dedupeKey: key)
        XCTAssertNotNil(rows)
        XCTAssertEqual(rows?.bodyText.contains("Quadriceps"), true)
        XCTAssertTrue((rows?.expiresAt ?? .distantPast) > referenceDate)
    }

    private func minimalSnapshot(
        acwr: ACWRResult? = nil,
        metrics: [DailyMetricSample] = [],
        isoWeek: ISOWeekIdentifier,
        referenceDate: Date? = nil
    ) -> ReflectionSnapshot {
        ReflectionSnapshot(
            referenceDate: referenceDate ?? self.referenceDate,
            isoWeek: isoWeek,
            volumeRows: [],
            acwr: acwr,
            exerciseProgress: [],
            dailyMetrics: metrics,
            proteinSamples: [],
            proteinTargetMinGrams: nil,
            weeklyProgress: WeeklyProgressInputs(
                sessionCount: 0,
                musclesCovered: [],
                topPR: nil,
                acwrZone: acwr?.zone,
                averageSleepHours: nil
            )
        )
    }

    private func insertQuadSession(sets: Int) throws {
        let session = WorkoutSession(
            title: "Legs",
            startTime: referenceDate,
            endTime: referenceDate,
            date: referenceDate,
            source: "test"
        )
        context.insert(session)

        let catalog = ExerciseCatalog(
            canonicalName: "Back Squat",
            primaryMuscles: [.quads],
            secondaryMuscles: [],
            movementPattern: .squat,
            equipment: .barbell
        )
        context.insert(catalog)

        let exercise = WorkoutExercise(exerciseTitle: "Back Squat", order: 0, catalogEntry: catalog)
        exercise.session = session
        session.exercises.append(exercise)

        for index in 0..<sets {
            let set = SetEntry(
                setIndex: index,
                setType: WorkoutSetType.normal.storageValue,
                weightKg: 100,
                reps: 5
            )
            set.exercise = exercise
            exercise.sets.append(set)
        }
        try context.save()
    }

    private func insertBalancedACWRSessions() throws {
        for offset in 0..<28 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: referenceDate) else { continue }
            let session = WorkoutSession(
                title: "Train",
                startTime: day,
                endTime: day,
                date: day,
                source: "test"
            )
            context.insert(session)
            let exercise = WorkoutExercise(exerciseTitle: "Work", order: 0)
            exercise.session = session
            session.exercises.append(exercise)
            for index in 0..<10 {
                let set = SetEntry(
                    setIndex: index,
                    setType: WorkoutSetType.normal.storageValue,
                    weightKg: 50,
                    reps: 5
                )
                set.exercise = exercise
                exercise.sets.append(set)
            }
        }
        try context.save()
    }

    private func fetchInsights(type: InsightType) throws -> [Insight] {
        let raw = type.rawValue
        let descriptor = FetchDescriptor<Insight>(predicate: #Predicate { $0.typeRaw == raw })
        return try context.fetch(descriptor)
    }

    private func fetchInsight(dedupeKey: String) throws -> Insight? {
        let descriptor = FetchDescriptor<Insight>(predicate: #Predicate { $0.dedupeKey == dedupeKey })
        return try context.fetch(descriptor).first
    }
}
