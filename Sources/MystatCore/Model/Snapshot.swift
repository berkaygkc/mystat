import Foundation

public struct Fact: Sendable, Equatable {
    public let label: String
    public let value: String
    /// Level if the value should be colored (e.g. "Heat 91°" in orange on the incident card).
    public let level: Level
    public init(_ label: String, _ value: String, level: Level = .ok) { self.label = label; self.value = value; self.level = level }
}

public struct ChildProcess: Sendable, Equatable {
    public let name: String
    public let cpuCores: Double
}

/// Processes grouped by meaning.
public struct ProcessGroup: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let context: String
    public var cpuCores: Double
    public var memoryGB: Double
    public var netMBps: Double
    public let uptime: String
    public let processCount: Int
    public let folder: String?
    public let terminal: String?
    public let port: Int?
    public let isOrphan: Bool
    public let relatedID: String?
    public let isDocker: Bool
    public var children: [ChildProcess]
    /// The group's processes (in live data; for stopping and disk writes). Empty in sample data.
    public var pids: [Int32] = []
    /// The group has processes not owned by the user; Stop / Force Quit are disabled.
    public var foreign = false
    /// From the process energy delta (W); 0 for a source without sensors.
    public var watts = 0.0
}

public struct Container: Identifiable, Sendable {
    public var id: String { dockerID.isEmpty ? name : dockerID }
    /// Compose service; otherwise the container name without the "/".
    public let name: String
    public let image: String
    /// 100% = 1 core (Docker's usual display).
    public var cpuPercent: Double
    public let memoryMB: Double
    /// false = unhealthy.
    public let healthy: Bool
    public let uptime: String
    /// Compose project; "" if none.
    public var project: String = ""
    public var dockerID: String = ""
    public var restarting: Bool = false
}

public enum IncidentKind: String, CaseIterable, Sendable { case cpu, memory, disk, docker, heat, battery }

public struct Incident: Sendable {
    public let kind: IncidentKind
    public let level: Level
    public let startedAt: String
    public let minutes: Int
    public let peakPercent: Double
    /// Identifiers of the culprits (group or container name) and the values to display, in the same order.
    public let culpritIDs: [String]
    public let culpritValues: [String]
    /// Unit of the culprit values: "cores", "GB", "W" …
    public let culpritUnit: String
    public let facts: [Fact]

    public init(kind: IncidentKind, level: Level, startedAt: String, minutes: Int, peakPercent: Double, culpritIDs: [String],
                culpritValues: [String], culpritUnit: String, facts: [Fact]) {
        self.kind = kind; self.level = level; self.startedAt = startedAt; self.minutes = minutes; self.peakPercent = peakPercent
        self.culpritIDs = culpritIDs; self.culpritValues = culpritValues; self.culpritUnit = culpritUnit; self.facts = facts
    }
}

public enum SuggestionTarget: Sendable, Equatable { case group(String), docker, disk([String]) }

public struct Suggestion: Sendable {
    public let title: String
    public let detail: String
    public let target: SuggestionTarget
}

public struct CPUState: Sendable {
    public var percent: Double
    public var systemPercent: Double
    public var cores: [Double]
    public var loadAvg: [Double]
}

public struct MemoryState: Sendable {
    public var percent: Double
    public var usedGB: Double
    public var totalGB: Double
    public var apps: Double, wired: Double, compressed: Double, free: Double
    public var pressurePercent: Double
    public var pressureLevel: Level
    public var swapGB: Double
}

public struct DiskState: Sendable {
    public var percent: Double
    public var freeGB: Double
    public var usedGB: Double
    public var purgeableGB: Double
    public var readMBps: Double
    public var writeMBps: Double
    /// Currently the heaviest disk writer (in sample data "Docker"); nil if unknown.
    public var topWriter: String? = nil
}

public struct NetState: Sendable {
    public var downMBps: Double
    public var upMBps: Double
    public var todayDownGB: Double
    public var todayUpGB: Double
    public var latencyMs: Double
    public var iface: String
    public var ssid: String
    public var details: [Fact]
    /// Reason the network name is missing (location permission, not Wi-Fi).
    public var ssidAccess: SSIDAccess = .known
    /// Whether per-app network is readable (kernel socket counters).
    public var perAppAvailable = true
    /// Whether the first rates have arrived (about 2 s after the section opens); if not, "Measuring…".
    public var perAppReady = true
}

public struct DockerDisk: Sendable {
    public var imagesGB: Double, imagesReclaimGB: Double, imagesCount: Int
    public var volumesGB: Double, volumesReclaimGB: Double, volumesCount: Int
    public var buildCacheGB: Double
    /// Space the virtual disk file occupies on disk; nil if unreadable.
    public var rawGB: Double?
    public var imagesUnusedCount = 0, volumesUnusedCount = 0
    /// Anonymous volumes only (safe cleanup; named data volumes are left alone).
    public var volumesAnonReclaimGB = 0.0, volumesAnonUnusedCount = 0
    public var buildCacheReclaimGB = 0.0, containersGB = 0.0

    /// Docker's data: images + volumes + build cache + container layers.
    public var dataGB: Double { imagesGB + volumesGB + buildCacheGB + containersGB }
}

public struct DockerState: Sendable {
    /// Whether Docker (the daemon) is reachable.
    public var running = true
    public var containers: [Container]
    public var vmMemoryGB: Double
    public var vmCores: Int
    public var disk: DockerDisk
    /// Change over the last 30 days (GB); nil if there is less than 2 days of data.
    public var trend30GB: Double? = nil

    public init(running: Bool = true, containers: [Container], vmMemoryGB: Double, vmCores: Int, disk: DockerDisk, trend30GB: Double? = nil) {
        self.running = running; self.containers = containers; self.vmMemoryGB = vmMemoryGB; self.vmCores = vmCores
        self.disk = disk; self.trend30GB = trend30GB
    }
}

public struct SystemState: Sendable {
    public var chipTemp: Double, gpuTemp: Double, ssdTemp: Double
    public var fanRPM: Double
    public var thermal: Level
    public var battery: Int
    public var charging: Bool
    /// Battery drain over the last 30 min (percentage points); nil if there is no incident.
    public var batteryDrain30m: Double?
    public var watts: Double
    public var adapter: String, health: String, capacity: String
    public var cycles: Int
    public var gpuPercent: Double
    public var gpuCores: Int
    public var onAC: Bool = true
    /// Bottom line of the sidebar ("MacBook Pro · M4 Pro / 14 cores · 48 GB · up 3 days").
    public var machine: MachineInfo? = nil
    /// 0: fanless Mac or unreadable.
    public var fanCount = 0
    /// Threshold for "fan quiet" (minimum speed).
    public var fanMinRPM = 0.0
    /// IOReport; nil if unreadable.
    public var cpuWatts: Double? = nil, gpuWatts: Double? = nil
    /// Apps using the GPU the most (descending).
    public var gpuApps: [(name: String, percent: Double)] = []
    public var displays = 0
}

public struct MachineInfo: Sendable, Equatable {
    public let model: String, chip: String
    public let pCores: Int, eCores: Int
    public let memoryGB: Int
    public let boot: Date

    public init(model: String, chip: String, pCores: Int, eCores: Int, memoryGB: Int, boot: Date) {
        self.model = model; self.chip = chip; self.pCores = pCores; self.eCores = eCores; self.memoryGB = memoryGB; self.boot = boot
    }

    public func footer(now: Date) -> String {
        L10n.t("machine.footer", ["model": model, "chip": chip, "cores": String(pCores + eCores), "mem": String(memoryGB),
                                  "uptime": Fmt.uptime(now.timeIntervalSince(boot))])
    }
}

public struct Snapshot: Sendable {
    public var cpu: CPUState
    public var memory: MemoryState
    public var disk: DiskState
    public var net: NetState
    public var docker: DockerState
    public var system: SystemState
    public var groups: [ProcessGroup]
    public var incident: Incident?
    public var suggestions: [Suggestion]
    public var calmTop: (name: String, percent: Int)
    public var capabilities: SourceCapabilities = .all
}
