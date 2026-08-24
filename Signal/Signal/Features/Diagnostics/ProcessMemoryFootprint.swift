import Darwin
import Foundation
import os

enum ProcessMemoryFootprint {
    struct Snapshot: Sendable {
        let footprintMB: Double
        let availableMB: Double?

        var diagnosticSuffix: String {
            let available = availableMB.map { String(format: "%.1f", $0) } ?? "na"
            return "footprintMB=\(String(format: "%.1f", footprintMB)) availableMB=\(available)"
        }
    }

    static func snapshot() -> Snapshot? {
        guard let footprintMB = physicalFootprintMB() else { return nil }
        return Snapshot(
            footprintMB: footprintMB,
            availableMB: osAvailableMemoryMB()
        )
    }

    static func diagnosticSuffix() -> String {
        snapshot()?.diagnosticSuffix ?? "footprintMB=na availableMB=na"
    }

    private static func physicalFootprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576.0
    }

    private static func osAvailableMemoryMB() -> Double? {
        let bytes = os_proc_available_memory()
        guard bytes > 0 else { return nil }
        return Double(bytes) / 1_048_576.0
    }
}
