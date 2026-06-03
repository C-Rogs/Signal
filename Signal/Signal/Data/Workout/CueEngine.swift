import Foundation
import os
import SwiftData

struct SetCueSnapshot: Sendable, Equatable {
    let setIndex: Int
    let weightKg: Double?
    let reps: Int?
    let rpe: Double?
    let isWarmup: Bool
}

struct ExerciseCueInput: Sendable, Equatable {
    let sessionID: String
    let exerciseID: String
    let mode: ExerciseLoggingMode
    let completedSet: SetCueSnapshot
    let priorSetInSession: SetCueSnapshot?
    let allCompletedSets: [SetCueSnapshot]
    let lastSessionSet: SetCueSnapshot?
    let targetReps: Int?
    let targetRIR: Int

    init(
        sessionID: String,
        exerciseID: String,
        mode: ExerciseLoggingMode,
        completedSet: SetCueSnapshot,
        priorSetInSession: SetCueSnapshot?,
        allCompletedSets: [SetCueSnapshot],
        lastSessionSet: SetCueSnapshot?,
        targetReps: Int?,
        targetRIR: Int = CueEngine.fallbackTargetRIR
    ) {
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.mode = mode
        self.completedSet = completedSet
        self.priorSetInSession = priorSetInSession
        self.allCompletedSets = allCompletedSets
        self.lastSessionSet = lastSessionSet
        self.targetReps = targetReps
        self.targetRIR = targetRIR
    }
}

enum CueTier: String, Sendable, CaseIterable {
    case smashed
    case strongPR
    case smallPR
    case onTrack
    case hardButOK
    case fatigue
    case stop
    case neutral
}

enum CueEngine {
    static let fallbackTargetRIR = 2

    static func cue(for input: ExerciseCueInput) -> String? {
        guard input.mode == .strength else { return nil }
        guard !input.completedSet.isWarmup else { return nil }

        let tier = classifyTier(for: input)
        guard tier != .neutral else { return nil }
        return message(for: tier, input: input)
    }

    static func tier(for input: ExerciseCueInput) -> CueTier {
        classifyTier(for: input)
    }

    static func targetReps(lastSessionSet: SetCueSnapshot?) -> Int? {
        lastSessionSet?.reps
    }

    // MARK: - Tier classification (first match wins)

    static func classifyTier(for input: ExerciseCueInput) -> CueTier {
        let current = input.completedSet
        let target = input.targetReps

        if isSmashed(current: current, targetReps: target) {
            return .smashed
        }
        if isStrongPR(current: current, last: input.lastSessionSet) {
            return .strongPR
        }
        if isSmallPR(current: current, last: input.lastSessionSet) {
            return .smallPR
        }
        if isOnTrack(current: current, targetReps: target) {
            return .onTrack
        }
        if isHardButOK(current: current, allCompleted: input.allCompletedSets) {
            return .hardButOK
        }
        if isFatigue(current: current, prior: input.priorSetInSession) {
            return .fatigue
        }
        if isStop(current: current, allCompleted: input.allCompletedSets) {
            return .stop
        }
        return .neutral
    }

    static func isSmashed(current: SetCueSnapshot, targetReps: Int?) -> Bool {
        guard let rpe = current.rpe, rpe <= 6 else { return false }
        guard let targetReps, let reps = current.reps else { return false }
        return reps >= targetReps + 2
    }

    static func isStrongPR(current: SetCueSnapshot, last: SetCueSnapshot?) -> Bool {
        guard let last else { return false }
        if let currentWeight = current.weightKg, let lastWeight = last.weightKg,
           currentWeight >= lastWeight * 1.05 - 0.000_1
        {
            return true
        }
        if let currentReps = current.reps, let lastReps = last.reps, currentReps >= lastReps + 2 {
            return true
        }
        return false
    }

    static func isSmallPR(current: SetCueSnapshot, last: SetCueSnapshot?) -> Bool {
        guard let last else { return false }
        if let currentWeight = current.weightKg, let lastWeight = last.weightKg,
           currentWeight > lastWeight + 0.000_1
        {
            return true
        }
        if let currentReps = current.reps, let lastReps = last.reps, currentReps > lastReps {
            return true
        }
        return false
    }

    static func isOnTrack(current: SetCueSnapshot, targetReps: Int?) -> Bool {
        guard let rpe = current.rpe, rpe >= 7, rpe <= 8 else { return false }
        guard let targetReps, let reps = current.reps else { return false }
        return abs(reps - targetReps) <= 1
    }

    static func isHardButOK(current: SetCueSnapshot, allCompleted: [SetCueSnapshot]) -> Bool {
        guard isHighRPE(current.rpe) else { return false }
        let priorHardCount = allCompleted.filter {
            $0.setIndex < current.setIndex && isHighRPE($0.rpe) && !$0.isWarmup
        }.count
        return priorHardCount == 0
    }

    static func isFatigue(current: SetCueSnapshot, prior: SetCueSnapshot?) -> Bool {
        guard let prior else { return false }
        if loadDropped(current: current, prior: prior) { return true }
        if repsDropped(current: current, prior: prior) { return true }
        return false
    }

    static func isStop(current: SetCueSnapshot, allCompleted: [SetCueSnapshot]) -> Bool {
        guard isHighRPE(current.rpe), !current.isWarmup else { return false }
        let priorHardSets = allCompleted.filter {
            $0.setIndex < current.setIndex && isHighRPE($0.rpe) && !$0.isWarmup
        }.count
        return priorHardSets >= 1
    }

    static func beatLastSession(current: SetCueSnapshot, last: SetCueSnapshot?) -> Bool {
        guard let last else { return false }
        if let currentWeight = current.weightKg, let lastWeight = last.weightKg {
            if currentWeight > lastWeight + 0.000_1 { return true }
            if currentWeight < lastWeight - 0.000_1 { return false }
        }
        if let currentReps = current.reps, let lastReps = last.reps, currentReps > lastReps {
            return true
        }
        return false
    }

    static func isHighRPE(_ rpe: Double?) -> Bool {
        guard let rpe else { return false }
        return rpe >= 9
    }

    private static func loadDropped(current: SetCueSnapshot, prior: SetCueSnapshot) -> Bool {
        guard let currentWeight = current.weightKg, let priorWeight = prior.weightKg else { return false }
        return currentWeight < priorWeight - 0.000_1
    }

    private static func repsDropped(current: SetCueSnapshot, prior: SetCueSnapshot) -> Bool {
        guard let currentReps = current.reps, let priorReps = prior.reps else { return false }
        return currentReps < priorReps - 1
    }

    // MARK: - Variant pools and selection

    enum LineKind {
        case win
        case nudge
        case plain
    }

    private static let variantPools: [CueTier: [(kind: LineKind, text: String)]] = [
        .smashed: [
            (.win, "Had more in you."),
            (.win, "Way above plan."),
            (.nudge, "Add load next set."),
            (.nudge, "One more rep next time."),
        ],
        .strongPR: [
            (.win, "Big jump."),
            (.win, "Crushed it."),
            (.win, "Bank that."),
        ],
        .smallPR: [
            (.win, "New best."),
            (.win, "Up from last time."),
            (.win, "Progress."),
        ],
        .onTrack: [
            (.plain, "Dialed in."),
            (.plain, "On plan."),
            (.plain, "Right where you want it."),
            (.plain, "Clean set."),
        ],
        .hardButOK: [
            (.plain, "Near your limit."),
            (.plain, "Good top set."),
            (.plain, "That's a quality rep."),
        ],
        .fatigue: [
            (.plain, "Back off slightly."),
            (.plain, "Same weight is fine."),
            (.plain, "Normal dip, hold here."),
        ],
        .stop: [
            (.plain, "Enough quality sets."),
            (.plain, "Stop here, volume is in."),
            (.plain, "Bank it."),
        ],
        .neutral: [
            (.plain, "Set logged."),
        ],
    ]

    static func message(for tier: CueTier, input: ExerciseCueInput) -> String {
        let pool = filteredPool(for: tier, input: input)
        let index = selectionIndex(
            sessionID: input.sessionID,
            exerciseID: input.exerciseID,
            setIndex: input.completedSet.setIndex,
            tier: tier,
            poolSize: pool.count
        )
        return pool[index].text
    }

    private static func filteredPool(
        for tier: CueTier,
        input: ExerciseCueInput
    ) -> [(kind: LineKind, text: String)] {
        guard let full = variantPools[tier], !full.isEmpty else {
            return [(.plain, "Set logged.")]
        }
        let hasWinNudge = full.contains { $0.kind == .win } && full.contains { $0.kind == .nudge }
        guard hasWinNudge else { return full }

        let beatLast = beatLastSession(current: input.completedSet, last: input.lastSessionSet)
        let kind: LineKind = beatLast ? .win : .nudge
        let filtered = full.filter { $0.kind == kind }
        return filtered.isEmpty ? full : filtered
    }

    static func selectionIndex(
        sessionID: String,
        exerciseID: String,
        setIndex: Int,
        tier: CueTier,
        poolSize: Int
    ) -> Int {
        guard poolSize > 0 else { return 0 }
        let key = sessionID + exerciseID + String(setIndex) + tier.rawValue
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return Int(hash % UInt64(poolSize))
    }
}

extension SetCueSnapshot {
    init(set: SetEntry) {
        setIndex = set.setIndex
        weightKg = set.weightKg
        reps = set.reps
        rpe = set.rpe
        isWarmup = WorkoutSetType(storageValue: set.setType) == .warmup
    }

    init(template: SetAutofillTemplate) {
        setIndex = template.setIndex
        weightKg = template.weightKg
        reps = template.reps
        rpe = template.rpe
        isWarmup = WorkoutSetType(storageValue: template.setType) == .warmup
    }
}

enum SetCueEvaluator {
    @MainActor
    static func cue(
        for set: SetEntry,
        exercise: WorkoutExercise,
        session: WorkoutSession,
        mode: ExerciseLoggingMode,
        in context: ModelContext
    ) -> String? {
        let sorted = exercise.sets.sorted { $0.setIndex < $1.setIndex }
        let completedSets = sorted.filter(\.isCompleted).map(SetCueSnapshot.init(set:))
        let prior = sorted
            .filter { $0.isCompleted && $0.setIndex < set.setIndex }
            .map(SetCueSnapshot.init(set:))
            .last { !$0.isWarmup }
        let lastTemplate = try? LastSessionAutofill.previousSet(
            catalogEntry: exercise.catalogEntry,
            exerciseTitle: exercise.exerciseTitle,
            setIndex: set.setIndex,
            mode: mode,
            in: context
        )
        let lastSessionSet = lastTemplate.map(SetCueSnapshot.init(template:))
        let input = ExerciseCueInput(
            sessionID: String(describing: session.persistentModelID),
            exerciseID: String(describing: exercise.persistentModelID),
            mode: mode,
            completedSet: SetCueSnapshot(set: set),
            priorSetInSession: prior,
            allCompletedSets: completedSets,
            lastSessionSet: lastSessionSet,
            targetReps: CueEngine.targetReps(lastSessionSet: lastSessionSet)
        )
        let tier = CueEngine.tier(for: input)
        guard tier != .neutral else {
            Log.workout.debug(
                "set cue setIndex=\(set.setIndex, privacy: .public) tier=neutral (no banner)"
            )
            return nil
        }
        let message = CueEngine.message(for: tier, input: input)
        Log.workout.debug(
            "set cue setIndex=\(set.setIndex, privacy: .public) tier=\(tier.rawValue, privacy: .public) message=\(message, privacy: .public)"
        )
        return message
    }
}
