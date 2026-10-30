import Darwin
import Foundation
import MystatCore

/// CPU ticks, virtual-memory counters, load average, swap and memory pressure. Needs no root.
public struct MachProbe: Sendable {
    public init() {}

    public func coreTicks() -> [CoreTicks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { i in
            func t(_ s: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[i * stride + Int(s)])) }
            return CoreTicks(user: t(CPU_STATE_USER), system: t(CPU_STATE_SYSTEM), idle: t(CPU_STATE_IDLE), nice: t(CPU_STATE_NICE))
        }
    }

    public func vm() -> VMCounters {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        _ = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        return VMCounters(pageSize: UInt64(getpagesize()), total: ProcessInfo.processInfo.physicalMemory,
                          free: UInt64(stats.free_count), active: UInt64(stats.active_count), inactive: UInt64(stats.inactive_count),
                          speculative: UInt64(stats.speculative_count), wired: UInt64(stats.wire_count),
                          compressor: UInt64(stats.compressor_page_count), purgeable: UInt64(stats.purgeable_count),
                          internal: UInt64(stats.internal_page_count), external: UInt64(stats.external_page_count),
                          swapUsed: swap.xsu_used,
                          pressureLevel: Self.int32("kern.memorystatus_vm_pressure_level") ?? 1,
                          memoryLevel: Self.int32("kern.memorystatus_level") ?? 100)
    }

    public func loadAverage() -> [Double] {
        var l = [Double](repeating: 0, count: 3)
        return getloadavg(&l, 3) == 3 ? l : [0, 0, 0]
    }

    static func int32(_ name: String) -> Int32? {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &v, &size, nil, 0) == 0 ? v : nil
    }
}

