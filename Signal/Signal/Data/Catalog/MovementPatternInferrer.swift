import Foundation

enum MovementPatternInferrer {
    static func infer(record: FreeExerciseDBRecord) -> MovementPattern {
        let name = record.name.lowercased()
        let category = record.category?.lowercased() ?? ""
        let mechanic = record.mechanic?.lowercased() ?? ""

        if category == "cardio" || name.contains("running") || name.contains("treadmill") || name.contains("cycling") {
            return .cardio
        }
        if category == "plyometrics" && (name.contains("jump") || name.contains("sprint")) {
            return .cardio
        }
        if name.contains("plank") || name.contains("crunch") || name.contains("sit-up") || name.contains("sit up") {
            return .core
        }
        if name.contains("carry") || name.contains("farmer") {
            return .carry
        }
        if name.contains("lunge") || name.contains("split squat") || name.contains("step-up") || name.contains("step up") {
            return .lunge
        }
        if name.contains("squat") || name.contains("leg press") || name.contains("leg extension") {
            return .squat
        }
        if name.contains("deadlift") || name.contains("rdl") || name.contains("good morning") || name.contains("hip thrust") {
            return .hinge
        }
        if name.contains("pull-up") || name.contains("pull up") || name.contains("chin-up") || name.contains("chin up") {
            return .verticalPull
        }
        if name.contains("pulldown") || name.contains("pull down") || name.contains("lat pull") {
            return .verticalPull
        }
        if name.contains("row") && !name.contains("upright row") {
            return .horizontalPull
        }
        if name.contains("bench press") || name.contains("push-up") || name.contains("push up") || name.contains("dip") && name.contains("chest") {
            return .horizontalPush
        }
        if name.contains("fly") || name.contains("crossover") {
            return .horizontalPush
        }
        if name.contains("overhead press") || name.contains("shoulder press") || name.contains("military press") {
            return .verticalPush
        }
        if record.force?.lowercased() == "push" && mechanic == "compound" && name.contains("press") {
            return .verticalPush
        }
        if mechanic == "isolation" || category == "stretching" {
            return .isolation
        }
        if record.force?.lowercased() == "pull" && mechanic == "compound" {
            return .horizontalPull
        }
        if record.force?.lowercased() == "push" && mechanic == "compound" {
            return .horizontalPush
        }
        return .isolation
    }
}
