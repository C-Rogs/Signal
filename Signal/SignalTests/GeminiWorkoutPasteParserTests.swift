import Foundation
import Testing
@testable import Signal

struct GeminiWorkoutPasteParserTests {
    private static let userSample = """
        FRIDAY EMERGENCY PUMP (Low Fatigue)

        Wide-Grip Lat Pulldown (Upper Lat Flush)
        Set 1: 45 kg x 12 (Warm-up)
        Set 2: 54 kg x 10 @ 7 RPE
        Set 3: 54 kg x 10 @ 8 RPE (Stop 2 reps short of failure)

        Machine Chest Press (Supported Pectoral Drive)
        Set 1: 40 kg x 12 (Warm-up)
        Set 2: 60 kg x 8 @ 7.5 RPE
        """

    @Test func fullUserSample() {
        let plan = GeminiWorkoutPasteParser.parse(Self.userSample)
        #expect(plan.title == "FRIDAY EMERGENCY PUMP (Low Fatigue)")
        #expect(plan.exercises.count == 2)
        #expect(plan.exercises[0].exerciseTitle == "Wide-Grip Lat Pulldown (Upper Lat Flush)")
        #expect(plan.exercises[0].sets.count == 3)
        #expect(plan.exercises[0].sets[0].isWarmup == true)
        #expect(plan.exercises[0].sets[1].rpe == 7)
        #expect(plan.exercises[0].sets[2].prescriptionNote == "Stop 2 reps short of failure")
        #expect(plan.exercises[1].sets[1].rpe == 7.5)
    }

    @Test func lbConversion() {
        let plan = GeminiWorkoutPasteParser.parse("""
            LEG DAY

            Squat
            Set 1: 225 lb x 5
            """)
        let weight = plan.exercises.first?.sets.first?.weightKg
        #expect(weight != nil)
        #expect(abs((weight ?? 0) - (225 * 0.45359237)) < 0.01)
    }

    @Test func lbDBs() {
        let plan = GeminiWorkoutPasteParser.parse("""
            ARMS

            Curl
            Set 1: 30 lb DBs x 12
            """)
        #expect(plan.exercises.first?.sets.first?.reps == 12)
        #expect(plan.exercises.first?.sets.first?.weightKg != nil)
    }

    @Test func kgDBs() {
        let plan = GeminiWorkoutPasteParser.parse("""
            SHOULDERS

            Lateral Raise
            Set 1: 8 kg DBs x 15
            """)
        #expect(plan.exercises.first?.sets.first?.weightKg == 8)
    }

    @Test func noRPE() {
        let plan = GeminiWorkoutPasteParser.parse("""
            PUSH

            Bench Press
            Set 1: 100 kg x 5
            """)
        #expect(plan.exercises.first?.sets.first?.rpe == nil)
    }

    @Test func warmupOnlyExercise() {
        let plan = GeminiWorkoutPasteParser.parse("""
            WARMUP BLOCK

            Row
            Set 1: 40 kg x 12 (warm up)
            Set 2: 50 kg x 10 (Warm-up)
            """)
        #expect(plan.exercises.first?.sets.allSatisfy(\.isWarmup) == true)
    }

    @Test func warmupCaseVariants() {
        let plan = GeminiWorkoutPasteParser.parse("""
            TEST

            Press
            Set 1: 20 kg x 10 (WARM-UP)
            Set 2: 40 kg x 8 (warmup)
            """)
        #expect(plan.exercises.first?.sets[0].isWarmup == true)
        #expect(plan.exercises.first?.sets[1].isWarmup == true)
    }

    @Test func blankLinesIgnored() {
        let plan = GeminiWorkoutPasteParser.parse("""

            TITLE


            Squat
            Set 1: 100 kg x 5

            """)
        #expect(plan.title == "TITLE")
        #expect(plan.exercises.count == 1)
    }

    @Test func titleMissingUsesWorkoutDefault() {
        let plan = GeminiWorkoutPasteParser.parse("""
            Wide-Grip Lat Pulldown
            Set 1: 45 kg x 12
            """)
        #expect(plan.title == "Workout")
        #expect(plan.exercises.first?.exerciseTitle == "Wide-Grip Lat Pulldown")
    }

    @Test func malformedSetLineSkipped() {
        let plan = GeminiWorkoutPasteParser.parse("""
            TEST

            Squat
            Not a set line
            Set 1: 100 kg x 5
            """)
        #expect(plan.skippedLines.contains("Not a set line"))
        #expect(plan.exercises.first?.sets.count == 1)
    }

    @Test func multipleExercisesOrdering() {
        let plan = GeminiWorkoutPasteParser.parse("""
            UPPER

            Row
            Set 1: 50 kg x 8

            Press
            Set 1: 60 kg x 8
            """)
        #expect(plan.exercises.map(\.exerciseTitle) == ["Row", "Press"])
    }

    @Test func prescriptionNoteOnSetLine() {
        let plan = GeminiWorkoutPasteParser.parse("""
            TEST

            Curl
            Set 1: 20 kg x 12 (Pause at bottom)
            """)
        #expect(plan.exercises.first?.sets.first?.prescriptionNote == "Pause at bottom")
        #expect(plan.exercises.first?.sets.first?.isWarmup == false)
    }

    @Test func decimalRPE() {
        let plan = GeminiWorkoutPasteParser.parse("""
            TEST

            Squat
            Set 1: 100 kg x 5 @ 7.5 RPE
            """)
        #expect(plan.exercises.first?.sets.first?.rpe == 7.5)
    }

    @Test func workoutTitleWithParens() {
        let plan = GeminiWorkoutPasteParser.parse("""
            FRIDAY EMERGENCY PUMP (Low Fatigue)

            Row
            Set 1: 50 kg x 8
            """)
        #expect(plan.title == "FRIDAY EMERGENCY PUMP (Low Fatigue)")
    }

    @Test func catalogMatchTitleStripsSubtitle() {
        let stripped = ParsedWorkoutTitle.catalogMatchTitle(from: "Wide-Grip Lat Pulldown (Upper Lat Flush)")
        #expect(stripped == "Wide-Grip Lat Pulldown")
    }

    @Test func emptyString() {
        let plan = GeminiWorkoutPasteParser.parse("")
        #expect(plan.exercises.isEmpty)
        #expect(plan.title == "Workout")
    }

    @Test func exerciseWithoutSetsExcluded() {
        let plan = GeminiWorkoutPasteParser.parse("""
            TEST

            Orphan Header

            Squat
            Set 1: 100 kg x 5
            """)
        #expect(plan.exercises.count == 1)
        #expect(plan.exercises.first?.exerciseTitle == "Squat")
    }

    @Test func setLineBeforeExerciseSkipped() {
        let plan = GeminiWorkoutPasteParser.parse("""
            TEST

            Set 1: 100 kg x 5

            Squat
            Set 1: 80 kg x 5
            """)
        #expect(plan.skippedLines.count == 1)
        #expect(plan.exercises.first?.sets.first?.weightKg == 80)
    }

    @Test func unicodeMultiplyAndBareRPE() {
        let plan = GeminiWorkoutPasteParser.parse("""
            PUMP

            Lat Pulldown
            54 kg × 10 @7
            54 kg × 10 @8
            """)
        #expect(plan.exercises.first?.sets.count == 2)
        #expect(plan.exercises.first?.sets[0].weightKg == 54)
        #expect(plan.exercises.first?.sets[0].reps == 10)
        #expect(plan.exercises.first?.sets[0].rpe == 7)
        #expect(plan.exercises.first?.sets[0].setIndex == 1)
        #expect(plan.exercises.first?.sets[1].setIndex == 2)
    }

    @Test func optionalSetPrefix() {
        let plan = GeminiWorkoutPasteParser.parse("""
            TEST

            Squat
            Set 1: 100 kg x 5
            100 kg x 5 @8
            """)
        #expect(plan.exercises.first?.sets.count == 2)
        #expect(plan.exercises.first?.sets[1].setIndex == 2)
        #expect(plan.exercises.first?.sets[1].rpe == 8)
    }

    @Test func exerciseRestAfterSets() {
        let plan = GeminiWorkoutPasteParser.parse("""
            LEGS

            Squat
            Set 1: 100 kg x 5
            Set 2: 100 kg x 5
            Rest: 90s

            Leg Press
            Set 1: 200 kg x 10
            """)
        #expect(plan.exercises[0].restDurationSeconds == 90)
        #expect(plan.exercises[1].restDurationSeconds == nil)
    }

    @Test func exerciseRestMinutes() {
        let plan = GeminiWorkoutPasteParser.parse("""
            PUSH

            Bench
            Set 1: 80 kg x 8
            Rest 2 min

            Fly
            Set 1: 20 kg x 12
            """)
        #expect(plan.exercises[0].restDurationSeconds == 120)
    }

    @Test func parentheticalRestLine() {
        let plan = GeminiWorkoutPasteParser.parse("""
            PULL

            Row
            Set 1: 50 kg x 8
            (90s rest)

            Curl
            Set 1: 20 kg x 12
            """)
        #expect(plan.exercises[0].restDurationSeconds == 90)
    }

    @Test func perSetRestBetweenSets() {
        let plan = GeminiWorkoutPasteParser.parse("""
            TEST

            Squat
            Set 1: 100 kg x 5
            Rest 60s
            Set 2: 100 kg x 5
            Rest 90s
            Set 3: 100 kg x 5
            """)
        let sets = plan.exercises.first?.sets ?? []
        #expect(sets[0].restDurationSeconds == 60)
        #expect(sets[1].restDurationSeconds == 90)
        #expect(sets[2].restDurationSeconds == nil)
    }

    @Test func restBeforeFirstSetIsExerciseDefault() {
        let plan = GeminiWorkoutPasteParser.parse("""
            TEST

            Squat
            Rest 75s
            Set 1: 100 kg x 5
            """)
        #expect(plan.exercises.first?.restDurationSeconds == 75)
    }
}
