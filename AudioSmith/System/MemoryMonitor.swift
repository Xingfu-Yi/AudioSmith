import Darwin
import Foundation
import MachO

struct MemoryMonitor: Sendable {
    static let minimumPhysicalBytes: UInt64 = 24 * 1_024 * 1_024 * 1_024
    static let warningBytes: UInt64 = 4_700_000_000
    static let releaseLimitBytes: UInt64 = 5_000_000_000

    var physicalMemoryBytes: UInt64 { ProcessInfo.processInfo.physicalMemory }
    var isSupported: Bool { physicalMemoryBytes >= Self.minimumPhysicalBytes }

    var formattedPhysicalMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(physicalMemoryBytes), countStyle: .memory)
    }

    func currentFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }
}

