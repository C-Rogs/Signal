import Foundation
import FoundationModels

struct DeviceClockTool: Tool {
    let name = "getDeviceClock"
    let description = "Current device date and time."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        CoachClockFormatter.format(referenceDate: Date())
    }
}
