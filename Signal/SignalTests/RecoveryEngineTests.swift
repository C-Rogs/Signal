import Foundation
import Testing
@testable import Signal

struct RecoveryEngineTests {
  @Test func rollingMeansUsesWindowedSamples() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))

    func day(offset: Int, hrv: Double, rhr: Double) -> DailyMetricSnapshot {
      let date = calendar.date(byAdding: .day, value: offset, to: end)!
      return DailyMetricSnapshot(
        date: date,
        hrvSDNN: hrv,
        restingHR: rhr,
        activeEnergy: nil,
        sleepHours: nil,
        bodyMassKg: nil,
        stepCount: nil,
        appleExerciseMinutes: nil
      )
    }

    let metrics = (-9...0).map { day(offset: $0, hrv: 50 + Double($0), rhr: 60) }
    let means = RecoveryEngine.rollingMeans(metrics: metrics, referenceDay: end, calendar: calendar)

    #expect(means.sevenDay.hrvSDNN != nil)
    #expect(means.thirtyDay.sampleDays == 10)
    #expect(means.sixtyDay.sampleDays == 10)
  }

  @Test func recoveryIndicatorScoresHigherHRV() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))

    var metrics: [DailyMetricSnapshot] = (-29...(-1)).map { offset in
      DailyMetricSnapshot(
        date: calendar.date(byAdding: .day, value: offset, to: end)!,
        hrvSDNN: 40,
        restingHR: 55,
        activeEnergy: nil,
        sleepHours: nil,
        bodyMassKg: nil,
        stepCount: nil,
        appleExerciseMinutes: nil
      )
    }
    metrics.append(
      DailyMetricSnapshot(
        date: end,
        hrvSDNN: 60,
        restingHR: 50,
        activeEnergy: nil,
        sleepHours: nil,
        bodyMassKg: nil,
        stepCount: nil,
        appleExerciseMinutes: nil
      )
    )

    let indicator = RecoveryEngine.recoveryIndicator(
      metrics: metrics,
      referenceDay: end,
      calendar: calendar
    )

    #expect(indicator.status == .recovered)
    #expect((indicator.score ?? 0) >= 70)
  }
}
