import Foundation
import Metal

/// Provides live system resource readings (CPU, memory, GPU, disk) from macOS APIs.
/// All properties are computed on demand — the caller polls at whatever cadence they need.
final class SystemResourceMonitor {

    // MARK: - CPU

    /// Overall CPU usage % (0-100) across all cores since the last tick.
    func cpuUsage() -> Double {
        let cpuInfo = hostCPULoadInfo()
        let totalTicks = cpuInfo.cpu_ticks.0 + cpuInfo.cpu_ticks.1
            + cpuInfo.cpu_ticks.2 + cpuInfo.cpu_ticks.3
        guard totalTicks > 0 else { return 0 }
        let idle = cpuInfo.cpu_ticks.0
        return (Double(totalTicks - idle) / Double(totalTicks)) * 100.0
    }

    /// Number of logical CPU cores.
    var processorCount: Int {
        ProcessInfo.processInfo.processorCount
    }

    /// Safe‑to‑display CPU label, e.g. "Apple M2 Ultra".
    var cpuModelLabel: String {
        if let name = sysctlString("machdep.cpu.brand_string"), !name.isEmpty {
            return name
        }
        return "Unknown CPU"
    }

    // MARK: - Memory

    /// Total physical RAM in bytes.
    var totalMemory: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// Used memory in bytes (active + wired + compressed).
    var usedMemory: UInt64 {
        let vm = hostVMInfo64()
        let pageSize = UInt64(vm_page_size)
        let active = UInt64(vm.active_count)
        let wired = UInt64(vm.wire_count)
        let compressed = UInt64(vm.compressor_page_count)
        return (active + wired + compressed) * pageSize
    }

    /// Memory usage fraction 0-1.
    var memoryFraction: Double {
        let total = totalMemory
        guard total > 0 else { return 0 }
        return Double(usedMemory) / Double(total)
    }

    // MARK: - GPU

    /// The name of the first Metal device, e.g. "Apple M2 Ultra".
    var gpuModelLabel: String? {
        MTLCreateSystemDefaultDevice()?.name
    }

    // MARK: - Disk

    /// Total disk capacity in bytes for the volume containing the app bundle.
    var totalDiskSpace: Int64? {
        try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        )[.systemSize] as? Int64
    }

    /// Free disk space in bytes.
    var freeDiskSpace: Int64? {
        try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        )[.systemFreeSize] as? Int64
    }

    /// Disk usage fraction 0-1.
    var diskFraction: Double {
        guard let total = totalDiskSpace, let free = freeDiskSpace, total > 0 else { return 0 }
        return Double(total - free) / Double(total)
    }

    // MARK: - Helpers

    private func hostCPULoadInfo() -> host_cpu_load_info {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, ptr, &count)
            }
        }
        if result != KERN_SUCCESS {
            return host_cpu_load_info()
        }
        return info
    }

    private func hostVMInfo64() -> vm_statistics64 {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, ptr, &count)
            }
        }
        if result != KERN_SUCCESS {
            return vm_statistics64()
        }
        return info
    }

    private func sysctlString(_ key: String) -> String? {
        var size = 0
        sysctlbyname(key, nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(key, &buf, &size, nil, 0)
        return String(cString: buf)
    }
}
