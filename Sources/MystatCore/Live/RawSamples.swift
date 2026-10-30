import Foundation

// Probe ↔ Core contract: raw counters read from the system. Meaning (percent, rate, group) is computed in Core.

/// Cumulative tick counters of one core (`host_processor_info`).
public struct CoreTicks: Sendable, Equatable {
    public var user, system, idle, nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

/// Virtual memory page counters (`host_statistics64`) and related sysctls.
public struct VMCounters: Sendable, Equatable {
    public var pageSize: UInt64
    /// Physical memory (bytes).
    public var total: UInt64
    public var free, active, inactive, speculative, wired, compressor, purgeable, `internal`, external: UInt64
    /// `vm.swapusage.xsu_used` (bytes).
    public var swapUsed: UInt64
    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    public var pressureLevel: Int32
    /// `kern.memorystatus_level`: percentage of available memory.
    public var memoryLevel: Int32

    public init(pageSize: UInt64, total: UInt64, free: UInt64, active: UInt64, inactive: UInt64, speculative: UInt64, wired: UInt64,
                compressor: UInt64, purgeable: UInt64, `internal`: UInt64, external: UInt64, swapUsed: UInt64, pressureLevel: Int32, memoryLevel: Int32) {
        self.pageSize = pageSize; self.total = total; self.free = free; self.active = active; self.inactive = inactive
        self.speculative = speculative; self.wired = wired; self.compressor = compressor; self.purgeable = purgeable
        self.`internal` = `internal`; self.external = external; self.swapUsed = swapUsed
        self.pressureLevel = pressureLevel; self.memoryLevel = memoryLevel
    }
}

/// If the interval between samples is longer than this (sleep/wake), the delta is discarded: 2 s tick × 3.
public enum SampleGap {
    public static let maxInterval: TimeInterval = 6
}

/// 64-bit byte counters of a network interface (`NET_RT_IFLIST2`).
public struct InterfaceCounters: Sendable, Equatable {
    public let name: String
    public let rx, tx: UInt64
    public let up: Bool
    public init(name: String, rx: UInt64, tx: UInt64, up: Bool) { self.name = name; self.rx = rx; self.tx = tx; self.up = up }
}

/// Capacity of the Data volume (bytes).
public struct VolumeCapacity: Sendable, Equatable {
    public let total, available, availableImportant: UInt64
    public init(total: UInt64, available: UInt64, availableImportant: UInt64) {
        self.total = total; self.available = available; self.availableImportant = availableImportant
    }
}

/// Cumulative read/write bytes of all block drivers (`IOBlockStorageDriver` → `Statistics`).
public struct DiskIOCounters: Sendable, Equatable {
    public let bytesRead, bytesWritten: UInt64
    public init(bytesRead: UInt64, bytesWritten: UInt64) { self.bytesRead = bytesRead; self.bytesWritten = bytesWritten }
}

/// Readable information about a process. For other users' processes (root, `_windowserver`…) libproc only
/// returns the path; then `restricted` is set and the counters are zero (there is no root helper).
public struct ProcessRecord: Sendable, Equatable {
    public let pid: Int32, ppid: Int32, uid: UInt32
    public let name: String
    public let path: String?
    public let args: [String]
    public let cwd: String?
    public let start: Date
    public let hasTTY: Bool
    /// User + system CPU time, in nanoseconds (the Mach unit is converted in the probe).
    public let cpuTime: UInt64
    /// User + system time of dead, reaped children, in nanoseconds (`ri_child_*`): short-lived jobs are attributed to their parent.
    public let childCPUTime: UInt64
    public let footprint: UInt64, energy: UInt64, diskWritten: UInt64
    public let restricted: Bool
    /// Nearest git root above the cwd (computed by the probe): gives context such as "acmecorp/web".
    public let projectRoot: String?
    /// `TERM_PROGRAM` from the process's environment (Ghostty, Terminal, iTerm2 …); only readable for the user's own processes.
    public let terminal: String?

    public init(pid: Int32, ppid: Int32, uid: UInt32, name: String, path: String?, args: [String], cwd: String?, start: Date, hasTTY: Bool,
                cpuTime: UInt64, footprint: UInt64, energy: UInt64, diskWritten: UInt64, restricted: Bool = false,
                projectRoot: String? = nil, terminal: String? = nil, childCPUTime: UInt64 = 0) {
        self.pid = pid; self.ppid = ppid; self.uid = uid; self.name = name; self.path = path; self.args = args; self.cwd = cwd
        self.start = start; self.hasTTY = hasTTY; self.cpuTime = cpuTime; self.footprint = footprint; self.energy = energy
        self.diskWritten = diskWritten; self.restricted = restricted; self.projectRoot = projectRoot; self.terminal = terminal
        self.childCPUTime = childCPUTime
    }
}

/// Battery and adapter (IOPowerSources + AppleSmartBattery).
public struct BatteryReading: Sendable, Equatable {
    public let percent: Double
    public let charging: Bool, onAC: Bool
    public let adapterWatts: Int?
    public let adapterUSBC: Bool
    public let cycles: Int?, designCapacity: Int?, maxCapacity: Int?

    public init(percent: Double, charging: Bool, onAC: Bool, adapterWatts: Int?, adapterUSBC: Bool,
                cycles: Int?, designCapacity: Int?, maxCapacity: Int?) {
        self.percent = percent; self.charging = charging; self.onAC = onAC; self.adapterWatts = adapterWatts
        self.adapterUSBC = adapterUSBC; self.cycles = cycles; self.designCapacity = designCapacity; self.maxCapacity = maxCapacity
    }

    public var adapterText: String { adapterWatts.map { "\($0) W" + (adapterUSBC ? " USB-C" : "") } ?? "—" }

    /// Health = maximum / design capacity: ≥ 80% good, ≥ 60% fair, below that poor.
    public var healthText: String {
        guard let d = designCapacity, d > 0, let m = maxCapacity else { return "—" }
        let pct = min(100, Double(m) / Double(d) * 100)
        return Fmt.pct(pct) + " · " + L10n.t(pct >= 80 ? "battery.health.good" : pct >= 60 ? "battery.health.fair" : "battery.health.weak")
    }

    public var capacityText: String {
        guard let d = designCapacity, let m = maxCapacity else { return "—" }
        return "\(Fmt.int(Double(m))) / \(Fmt.int(Double(d))) mAh"
    }
}
