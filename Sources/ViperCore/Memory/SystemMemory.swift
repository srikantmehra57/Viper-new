import Darwin
import Foundation

/// How hard macOS is working to find memory, mirroring Activity Monitor's pressure states.
public enum MemoryPressure: String, Sendable { case normal, warning, critical }

/// A snapshot of whole-machine memory, matching the numbers Activity Monitor shows.
public struct MemoryStatus: Sendable, Equatable {
    public var total: UInt64
    /// App + wired + compressed; Activity Monitor's "Memory Used".
    public var used: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    /// File-backed and purgeable memory macOS can drop on demand.
    public var cached: UInt64
    public var free: UInt64
    public var swapUsed: UInt64
    public var pressure: MemoryPressure

    public init(total: UInt64, used: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64, free: UInt64, swapUsed: UInt64, pressure: MemoryPressure) {
        self.total = total
        self.used = used
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.free = free
        self.swapUsed = swapUsed
        self.pressure = pressure
    }
}

/// Whole-machine memory figures from the Mach VM counters.
public enum SystemMemory {
    public static func read() -> MemoryStatus {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        let page = UInt64(vm_kernel_page_size)
        func pages(_ keyPath: KeyPath<vm_statistics64_data_t, natural_t>) -> UInt64 {
            result == KERN_SUCCESS ? UInt64(stats[keyPath: keyPath]) * page : 0
        }
        let wired = pages(\.wire_count)
        let compressed = pages(\.compressor_page_count)
        let cached = pages(\.purgeable_count) + pages(\.external_page_count)
        let app = pages(\.internal_page_count) - pages(\.purgeable_count)
        return MemoryStatus(
            total: ProcessInfo.processInfo.physicalMemory,
            used: app + wired + compressed,
            wired: wired, compressed: compressed, cached: cached,
            free: pages(\.free_count),
            swapUsed: swapUsed(), pressure: pressure())
    }

    private static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    /// The kernel's own pressure level: 1 normal, 2 warning, 4 critical. Unknown reads as normal.
    private static func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 2: return .warning
        case 4: return .critical
        default: return .normal
        }
    }
}
