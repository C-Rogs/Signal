import XCTest
@testable import Signal

final class WorkoutHistoryDetailFormattingTests: XCTestCase {
    func testStrengthLoadLineIncludesRPEForWorkingSet() {
        let line = WorkoutHistoryDetailFormatting.strengthLoadLine(
            weightLabel: "72.5 kg",
            reps: 10,
            rpe: 8.5,
            setType: .normal
        )
        XCTAssertEqual(line, "72.5 kg × 10 · RPE 8.5")
    }

    func testStrengthLoadLineOmitsRPEWhenNil() {
        let line = WorkoutHistoryDetailFormatting.strengthLoadLine(
            weightLabel: "60 kg",
            reps: 8,
            rpe: nil,
            setType: .normal
        )
        XCTAssertEqual(line, "60 kg × 8")
    }

    func testStrengthLoadLineOmitsRPEForWarmupEvenWhenPresent() {
        let line = WorkoutHistoryDetailFormatting.strengthLoadLine(
            weightLabel: "40 kg",
            reps: 12,
            rpe: 7,
            setType: .warmup
        )
        XCTAssertEqual(line, "40 kg × 12")
    }

    func testMeanWorkingSetRPEIgnoresWarmupsAndNilRPE() {
        let sets = [
            makeSet(setType: .warmup, rpe: 6),
            makeSet(setType: .normal, rpe: 8),
            makeSet(setType: .normal, rpe: nil),
            makeSet(setType: .normal, rpe: 9),
        ]
        XCTAssertEqual(WorkoutHistoryDetailFormatting.meanWorkingSetRPE(sets: sets), 8.5)
    }

    func testMeanWorkingSetRPENilWhenNoWorkingSetsWithRPE() {
        let sets = [
            makeSet(setType: .warmup, rpe: 7),
            makeSet(setType: .normal, rpe: nil),
        ]
        XCTAssertNil(WorkoutHistoryDetailFormatting.meanWorkingSetRPE(sets: sets))
    }

    func testMeanRPELabelSnapsToPickerScale() {
        XCTAssertEqual(WorkoutHistoryDetailFormatting.meanRPELabel(for: 8.25), "8")
    }

    private func makeSet(setType: WorkoutSetType, rpe: Double?) -> SetEntry {
        SetEntry(
            setIndex: 0,
            setType: setType.storageValue,
            rpe: rpe
        )
    }
}
