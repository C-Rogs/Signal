import Foundation
import HealthKit

enum HealthKitQueryErrors {
    static func isNoData(_ error: Error) -> Bool {
        guard let hkError = error as? HKError else { return false }
        return hkError.code == .errorNoData
    }
}
