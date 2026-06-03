import XCTest
@testable import Signal

final class VolumeCalculatorTests: XCTestCase {
    func testWarmupExcludedFromVolume() {
        let warmup = SetEntry(setIndex: 0, setType: WorkoutSetType.warmup.storageValue, weightKg: 60, reps: 10)
        let working = SetEntry(setIndex: 1, setType: WorkoutSetType.normal.storageValue, weightKg: 100, reps: 5)
        let contributions = [
            VolumeSetContribution(set: warmup, primaryMuscles: [.chest], secondaryMuscles: []),
            VolumeSetContribution(set: working, primaryMuscles: [.chest], secondaryMuscles: []),
        ]
        let volume = VolumeCalculator.fractionalVolume(for: contributions)
        XCTAssertEqual(volume[.chest]!, 1.0, accuracy: 0.001)
    }

    func testPrimaryCountsOneSecondaryHalf() {
        let set = SetEntry(setIndex: 0, setType: WorkoutSetType.normal.storageValue, weightKg: 80, reps: 8)
        let contributions = [
            VolumeSetContribution(
                set: set,
                primaryMuscles: [.chest],
                secondaryMuscles: [.triceps]
            ),
        ]
        let volume = VolumeCalculator.fractionalVolume(for: contributions)
        XCTAssertEqual(volume[.chest]!, 1.0, accuracy: 0.001)
        XCTAssertEqual(volume[.triceps]!, 0.5, accuracy: 0.001)
    }

    func testSecondaryOverlappingPrimaryNotDoubleCounted() {
        let set = SetEntry(setIndex: 0, setType: WorkoutSetType.normal.storageValue, weightKg: 80, reps: 8)
        let contributions = [
            VolumeSetContribution(
                set: set,
                primaryMuscles: [.chest],
                secondaryMuscles: [.chest, .triceps]
            ),
        ]
        let volume = VolumeCalculator.fractionalVolume(for: contributions)
        XCTAssertEqual(volume[.chest]!, 1.0, accuracy: 0.001)
        XCTAssertEqual(volume[.triceps]!, 0.5, accuracy: 0.001)
    }
}
