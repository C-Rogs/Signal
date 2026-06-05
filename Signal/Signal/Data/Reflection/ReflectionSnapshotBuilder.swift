import Foundation
import SwiftData

enum ReflectionSnapshotBuilder {
  @MainActor
  static func build(in context: ModelContext, calendar: Calendar, referenceDate: Date = Date()) -> ReflectionSnapshot {
    let isoWeek = ISOWeekIdentifier.current(calendar: calendar, referenceDate: referenceDate)
    let volumeMap = currentWeekVolume(in: context, calendar: calendar, referenceDate: referenceDate)
    let volumeRows = MuscleGroup.allCases.map { group in
      let sets = volumeMap[group] ?? 0
      let landmarks = group.landmarks
      return VolumeInsightRow(
        muscleGroup: group,
        fractionalSets: sets,
        status: VolumeStatus.status(fractionalSets: sets, landmarks: landmarks),
        mev: landmarks.mev,
        mrv: landmarks.mrv
      )
    }

    let acwr = computeACWR(in: context, calendar: calendar, referenceDate: referenceDate)
    let exerciseProgress = fetchExerciseProgress(in: context)
    let dailyMetrics = fetchRecentDailyMetrics(in: context, calendar: calendar, referenceDate: referenceDate)
    let proteinSamples = fetchRecentProtein(in: context, calendar: calendar, referenceDate: referenceDate)
    let referenceDay = calendar.startOfDay(for: referenceDate)
    let proteinTarget = computeProteinTarget(in: context, referenceDay: referenceDay)
    let weeklyProgress = buildWeeklyProgress(
      in: context,
      calendar: calendar,
      referenceDate: referenceDate,
      acwr: acwr,
      dailyMetrics: dailyMetrics
    )

    return ReflectionSnapshot(
      referenceDate: referenceDate,
      isoWeek: isoWeek,
      volumeRows: volumeRows,
      acwr: acwr,
      exerciseProgress: exerciseProgress,
      dailyMetrics: dailyMetrics,
      proteinSamples: proteinSamples,
      proteinTargetMinGrams: proteinTarget?.targetMinGrams,
      weeklyProgress: weeklyProgress,
      activeDisruptors: [],
      personalReadiness: nil,
      exertionDebt: nil,
      todayExertion: nil,
      deloadSuggested: false
    )
  }

  @MainActor
  static func enrichWithRecoveryContext(
    _ snapshot: ReflectionSnapshot,
    in context: ModelContext,
    calendar: Calendar
  ) -> ReflectionSnapshot {
    let referenceDay = calendar.startOfDay(for: snapshot.referenceDate)
    let metricSnapshots = snapshot.dailyMetrics.map { sample in
      DailyMetricSnapshot(
        date: sample.date,
        hrvSDNN: sample.hrvSDNN_ms,
        restingHR: sample.restingHR,
        activeEnergy: nil,
        sleepHours: sample.sleepHours,
        bodyMassKg: nil,
        stepCount: nil,
        appleExerciseMinutes: nil,
        wristTemperatureDeltaC: sample.wristTemperatureDeltaC
      )
    }
    let score = RecoveryScoreCalculator.compute(
      metrics: metricSnapshots,
      referenceDay: referenceDay,
      calendar: calendar
    )
    let episodes = RecoveryDisruptorEngine.activeEpisodes(
      in: context,
      referenceDay: referenceDay,
      calendar: calendar
    )
    let exertionContext = ExertionContextBuilder.build(
      in: context,
      referenceDay: referenceDay,
      calendar: calendar,
      acwr: snapshot.acwr
    )
    let profile = PersonalReadinessCalculator.compute(
      metrics: metricSnapshots,
      todayScore: score,
      activeEpisodes: episodes,
      referenceDay: referenceDay,
      calendar: calendar,
      exertionDebtNormalized: exertionContext.exertionDebt.isCalibrated
        ? exertionContext.exertionDebt.exertionDebtNormalized
        : nil
    )
    return ReflectionSnapshot(
      referenceDate: snapshot.referenceDate,
      isoWeek: snapshot.isoWeek,
      volumeRows: snapshot.volumeRows,
      acwr: snapshot.acwr,
      exerciseProgress: snapshot.exerciseProgress,
      dailyMetrics: snapshot.dailyMetrics,
      proteinSamples: snapshot.proteinSamples,
      proteinTargetMinGrams: snapshot.proteinTargetMinGrams,
      weeklyProgress: snapshot.weeklyProgress,
      activeDisruptors: episodes,
      personalReadiness: profile,
      exertionDebt: exertionContext.exertionDebt,
      todayExertion: exertionContext.exertionDebt.todayExertion,
      deloadSuggested: exertionContext.deloadSuggested
    )
  }

  @MainActor
  private static func fetchExerciseProgress(in context: ModelContext) -> [ExerciseProgressSample] {
    let descriptor = FetchDescriptor<ExerciseProgress>(
      sortBy: [SortDescriptor(\.sessionDate, order: .forward)]
    )
    let rows = (try? context.fetch(descriptor)) ?? []
    let catalogNames = exerciseDisplayNames(in: context)
    return rows.map { row in
      ExerciseProgressSample(
        exerciseID: row.exerciseID,
        displayName: catalogNames[row.exerciseID] ?? row.exerciseID,
        sessionDate: row.sessionDate,
        e1RMKg: row.e1RM_kg
      )
    }
  }

  @MainActor
  private static func exerciseDisplayNames(in context: ModelContext) -> [String: String] {
    let descriptor = FetchDescriptor<ExerciseCatalog>()
    let catalog = (try? context.fetch(descriptor)) ?? []
    var names: [String: String] = [:]
    for entry in catalog {
      names[entry.canonicalName] = entry.canonicalName
    }
    return names
  }

  @MainActor
  private static func currentWeekVolume(
    in context: ModelContext,
    calendar: Calendar,
    referenceDate: Date
  ) -> [MuscleGroup: Double] {
    let today = calendar.startOfDay(for: referenceDate)
    guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else {
      return [:]
    }
    let descriptor = FetchDescriptor<WorkoutSession>(
      predicate: #Predicate { session in
        session.endTime != nil && session.date >= weekStart
      },
      sortBy: [SortDescriptor(\.date, order: .forward)]
    )
    let sessions = (try? context.fetch(descriptor)) ?? []
    var contributions: [VolumeSetContribution] = []
    for session in sessions {
      for exercise in session.exercises {
        contributions.append(contentsOf: VolumeCalculator.contributions(from: exercise))
      }
    }
    return VolumeCalculator.fractionalVolume(for: contributions)
  }

  @MainActor
  private static func computeACWR(
    in context: ModelContext,
    calendar: Calendar,
    referenceDate: Date
  ) -> ACWRResult? {
    let today = calendar.startOfDay(for: referenceDate)
    guard let rangeStart = calendar.date(byAdding: .day, value: -27, to: today) else {
      return nil
    }
    let descriptor = FetchDescriptor<WorkoutSession>(
      predicate: #Predicate { session in
        session.endTime != nil && session.date >= rangeStart
      },
      sortBy: [SortDescriptor(\.date, order: .forward)]
    )
    let sessions = (try? context.fetch(descriptor)) ?? []
    var loadsByDay: [Date: Double] = [:]
    for session in sessions {
      let day = calendar.startOfDay(for: session.date)
      var count = 0.0
      for exercise in session.exercises {
        for set in exercise.sets where WorkoutSetType(storageValue: set.setType) != .warmup {
          count += 1
        }
      }
      loadsByDay[day, default: 0] += count
    }
    let dailyLoads = loadsByDay.map { (date: $0.key, totalSets: Int($0.value.rounded())) }
    return ACWRCalculator.compute(dailyLoads: dailyLoads, referenceDate: today, calendar: calendar)
  }

  @MainActor
  private static func computeProteinTarget(in context: ModelContext, referenceDay: Date) -> ProteinTarget? {
    let profileDescriptor = FetchDescriptor<UserProfile>()
    let profile = try? context.fetch(profileDescriptor).first
    guard let bodyweight = profile?.bodyweightKg else { return nil }
    let day = referenceDay
    let nutritionDescriptor = FetchDescriptor<DailyNutrition>(
      predicate: #Predicate { nutrition in
        nutrition.date == day
      }
    )
    guard let proteinG = try? context.fetch(nutritionDescriptor).first?.proteinG else {
      return nil
    }
    return ProteinTarget(bodyweightKg: bodyweight, actualGrams: proteinG)
  }

  @MainActor
  private static func fetchRecentDailyMetrics(
    in context: ModelContext,
    calendar: Calendar,
    referenceDate: Date
  ) -> [DailyMetricSample] {
    let ref = calendar.startOfDay(for: referenceDate)
    guard let start = calendar.date(byAdding: .day, value: -64, to: ref) else { return [] }
    let descriptor = FetchDescriptor<DailyMetric>(
      predicate: #Predicate { $0.date >= start && $0.date <= ref },
      sortBy: [SortDescriptor(\.date, order: .forward)]
    )
    let rows = (try? context.fetch(descriptor)) ?? []
    return rows.map {
      DailyMetricSample(
        date: $0.date,
        hrvSDNN_ms: $0.hrvSDNN_ms,
        restingHR: $0.restingHR,
        sleepHours: $0.sleepHours,
        wristTemperatureDeltaC: $0.wristTemperatureDeltaC
      )
    }
  }

  @MainActor
  private static func fetchRecentProtein(
    in context: ModelContext,
    calendar: Calendar,
    referenceDate: Date
  ) -> [DailyProteinSample] {
    let ref = calendar.startOfDay(for: referenceDate)
    guard let start = calendar.date(byAdding: .day, value: -6, to: ref) else { return [] }
    let descriptor = FetchDescriptor<DailyNutrition>(
      predicate: #Predicate { $0.date >= start && $0.date <= ref },
      sortBy: [SortDescriptor(\.date, order: .forward)]
    )
    let rows = (try? context.fetch(descriptor)) ?? []
    return rows.map { DailyProteinSample(date: $0.date, proteinG: $0.proteinG) }
  }

  @MainActor
  private static func buildWeeklyProgress(
    in context: ModelContext,
    calendar: Calendar,
    referenceDate: Date,
    acwr: ACWRResult?,
    dailyMetrics: [DailyMetricSample]
  ) -> WeeklyProgressInputs {
    let ref = calendar.startOfDay(for: referenceDate)
    guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: ref)?.start else {
      return WeeklyProgressInputs(
        sessionCount: 0,
        musclesCovered: [],
        topPR: nil,
        acwrZone: acwr?.zone,
        averageSleepHours: nil
      )
    }

    let sessionDescriptor = FetchDescriptor<WorkoutSession>(
      predicate: #Predicate { $0.endTime != nil && $0.date >= weekStart },
      sortBy: [SortDescriptor(\.date, order: .forward)]
    )
    let sessions = (try? context.fetch(sessionDescriptor)) ?? []
    var muscleSet: Set<MuscleGroup> = []
    for session in sessions {
      for exercise in session.exercises {
        let contributions = VolumeCalculator.contributions(from: exercise)
        let volume = VolumeCalculator.fractionalVolume(for: contributions)
        for (muscle, sets) in volume where sets > 0 {
          muscleSet.insert(muscle)
        }
      }
    }

    let topPR = topWeeklyPR(in: context, calendar: calendar, weekStart: weekStart, referenceDate: ref)
    let sleepValues = dailyMetrics.compactMap(\.sleepHours)
    let avgSleep = sleepValues.isEmpty ? nil : sleepValues.reduce(0, +) / Double(sleepValues.count)

    return WeeklyProgressInputs(
      sessionCount: sessions.count,
      musclesCovered: muscleSet.sorted { $0.rawValue < $1.rawValue },
      topPR: topPR,
      acwrZone: acwr?.zone,
      averageSleepHours: avgSleep
    )
  }

  @MainActor
  private static func topWeeklyPR(
    in context: ModelContext,
    calendar: Calendar,
    weekStart: Date,
    referenceDate: Date
  ) -> WeeklyPRHighlight? {
    let priorDescriptor = FetchDescriptor<ExerciseProgress>(
      predicate: #Predicate { $0.sessionDate < weekStart },
      sortBy: [SortDescriptor(\.sessionDate, order: .reverse)]
    )
    let priorRows = (try? context.fetch(priorDescriptor)) ?? []
    var priorBest: [String: Double] = [:]
    for row in priorRows {
      let current = priorBest[row.exerciseID] ?? 0
      if row.e1RM_kg > current {
        priorBest[row.exerciseID] = row.e1RM_kg
      }
    }

    let weekDescriptor = FetchDescriptor<ExerciseProgress>(
      predicate: #Predicate { $0.sessionDate >= weekStart && $0.sessionDate <= referenceDate },
      sortBy: [SortDescriptor(\.e1RM_kg, order: .reverse)]
    )
    let weekRows = (try? context.fetch(weekDescriptor)) ?? []
    let catalogNames = exerciseDisplayNames(in: context)

    var bestPR: WeeklyPRHighlight?
    for row in weekRows {
      let previous = priorBest[row.exerciseID] ?? 0
      guard row.e1RM_kg > previous + 0.01 else { continue }
      let name = catalogNames[row.exerciseID] ?? row.exerciseID
      if let current = bestPR {
        if row.e1RM_kg > current.e1RMKg {
          bestPR = WeeklyPRHighlight(name: name, e1RMKg: row.e1RM_kg)
        }
      } else {
        bestPR = WeeklyPRHighlight(name: name, e1RMKg: row.e1RM_kg)
      }
    }
    return bestPR
  }
}
