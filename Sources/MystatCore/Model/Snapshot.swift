import Foundation

public struct Fact: Sendable, Equatable {
    public let label: String
    public let value: String
    /// Değer renklenecekse seviyesi (ör. olay kartında "Isı 91°" turuncu).
    public let level: Level
    public init(_ label: String, _ value: String, level: Level = .ok) { self.label = label; self.value = value; self.level = level }
}

public struct ChildProcess: Sendable, Equatable {
    public let name: String
    public let cpuCores: Double
}

/// Anlamına göre gruplanmış süreçler (spec §8).
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
    /// Grubun süreçleri (canlı veride; durdurma ve disk yazımı için). Örnek veride boş.
    public var pids: [Int32] = []
    /// Grupta kullanıcının olmayan süreç var; Durdur / Zorla kapat pasif (spec §7.4).
    public var foreign = false
}

public struct Container: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let image: String
    public var cpuPercent: Double
    public let memoryMB: Double
    public let healthy: Bool
    public let uptime: String
}

public enum IncidentKind: String, CaseIterable, Sendable { case cpu, memory, disk, docker, heat, battery }

public struct Incident: Sendable {
    public let kind: IncidentKind
    public let level: Level
    public let startedAt: String
    public let minutes: Int
    public let peakPercent: Double
    /// Sorumluların kimlikleri (grup ya da container adı) ve görüntülenecek değerleri, aynı sırada.
    public let culpritIDs: [String]
    public let culpritValues: [String]
    /// Sorumlu değerlerinin birimi: "çekirdek", "GB", "W" …
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
}

public struct DockerDisk: Sendable {
    public var imagesGB: Double, imagesReclaimGB: Double, imagesCount: Int
    public var volumesGB: Double, volumesReclaimGB: Double, volumesCount: Int
    public var buildCacheGB: Double
    public var rawGB: Double
}

public struct DockerState: Sendable {
    public var project: String
    public var containers: [Container]
    public var vmMemoryGB: Double
    public var vmCores: Int
    public var disk: DockerDisk
}

public struct SystemState: Sendable {
    public var chipTemp: Double, gpuTemp: Double, ssdTemp: Double
    public var fanRPM: Double
    public var thermal: Level
    public var battery: Int
    public var charging: Bool
    /// Son 30 dk'daki pil erimesi (yüzde puan); olay yoksa nil.
    public var batteryDrain30m: Double?
    public var watts: Double
    public var adapter: String, health: String, capacity: String
    public var cycles: Int
    public var gpuPercent: Double
    public var gpuCores: Int
    public var onAC: Bool = true
    /// Kenar menüsünün alt satırı ("MacBook Pro · M4 Pro / 14 çekirdek · 48 GB · açık 3 gün").
    public var machine: MachineInfo? = nil
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
        "\(model) · \(chip)\n\(pCores + eCores) çekirdek · \(memoryGB) GB · açık \(Fmt.uptime(now.timeIntervalSince(boot)))"
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
