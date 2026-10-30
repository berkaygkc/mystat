import Foundation

/// Measurements of one sampling round (the live source fills them in, `SnapshotBuilder` gives them meaning).
/// Summary of one sensor round (chip, fan and system power always; GPU temperature, IOReport and GPU apps only when someone is looking).
public struct SensorReading: Sendable {
    public var chipTemp: Double
    public var gpuTemp: Double?, ssdTemp: Double?, batteryTemp: Double?
    public var fanRPM: Double, fanCount: Int, fanMinRPM: Double
    public var systemWatts: Double?
    public var cpuWatts: Double?, gpuWatts: Double?
    public var gpuPercent: Double, gpuCores: Int
    public var gpuApps: [(name: String, percent: Double)]

    public init(chipTemp: Double, gpuTemp: Double?, ssdTemp: Double?, batteryTemp: Double?, fanRPM: Double, fanCount: Int, fanMinRPM: Double,
                systemWatts: Double?, cpuWatts: Double?, gpuWatts: Double?, gpuPercent: Double, gpuCores: Int, gpuApps: [(name: String, percent: Double)]) {
        self.chipTemp = chipTemp; self.gpuTemp = gpuTemp; self.ssdTemp = ssdTemp; self.batteryTemp = batteryTemp
        self.fanRPM = fanRPM; self.fanCount = fanCount; self.fanMinRPM = fanMinRPM; self.systemWatts = systemWatts
        self.cpuWatts = cpuWatts; self.gpuWatts = gpuWatts; self.gpuPercent = gpuPercent; self.gpuCores = gpuCores; self.gpuApps = gpuApps
    }
}

public struct LiveMeasurements: Sendable {
    public var cpu: CPUState
    public var memory: MemoryState
    public var disk: DiskState
    public var net: (down: Double, up: Double, todayDown: Double, todayUp: Double)
    public var iface: String
    public var ip: String?
    public var groups: [ProcessGroup]
    public var thermal: Level
    public var battery: BatteryReading?
    public var batteryDrain30m: Double?
    public var machine: MachineInfo
    /// Large, old files in Downloads (≥ 2 GB, not opened for ≥ 14 days).
    public var downloads: [(name: String, gb: Double, idleDays: Int)]
    public var coreCount: Int
    public var docker: DockerState
    /// nil if there are no sensors: the System section shows its calm state.
    public var sensors: SensorReading?
    /// While the Network section is open: primary connection, router latency, whether per-app network is readable.
    public var link: NetLink? = nil
    public var latencyMs: Double? = nil
    public var perAppAvailable = true
    public var perAppReady = true
    /// State of the location permission when the Wi-Fi network name is missing.
    public var ssidAccess: SSIDAccess = .needsPermission

    public init(cpu: CPUState, memory: MemoryState, disk: DiskState, net: (down: Double, up: Double, todayDown: Double, todayUp: Double),
                iface: String, ip: String?, groups: [ProcessGroup], thermal: Level, battery: BatteryReading?, batteryDrain30m: Double?,
                machine: MachineInfo, downloads: [(name: String, gb: Double, idleDays: Int)], coreCount: Int, docker: DockerState = .notRunning,
                sensors: SensorReading? = nil) {
        self.docker = docker
        self.sensors = sensors
        self.cpu = cpu; self.memory = memory; self.disk = disk; self.net = net; self.iface = iface; self.ip = ip; self.groups = groups
        self.thermal = thermal; self.battery = battery; self.batteryDrain30m = batteryDrain30m; self.machine = machine
        self.downloads = downloads; self.coreCount = coreCount
    }
}

/// The Snapshot the UI sees, built from measurements: the busiest group for the calm headline, suggestions, network and system facts.
public enum SnapshotBuilder {
    public static func build(_ m: LiveMeasurements, incident: Incident?, capabilities: SourceCapabilities) -> Snapshot {
        var s = Snapshot.empty(capabilities: capabilities)
        s.cpu = m.cpu
        // On Apple Silicon the first logical CPUs are the efficiency cluster (ioreg cluster-type); the UI shows performance cores first.
        let e = m.machine.eCores
        if e > 0, m.machine.pCores + e == m.cpu.cores.count { s.cpu.cores = Array(m.cpu.cores[e...] + m.cpu.cores[..<e]) }
        s.memory = m.memory
        s.disk = m.disk
        var net = NetState(downMBps: m.net.down, upMBps: m.net.up, todayDownGB: m.net.todayDown, todayUpGB: m.net.todayUp,
                           latencyMs: m.latencyMs ?? .nan, iface: m.link?.displayName ?? m.iface, ssid: m.link?.wifi?.ssid ?? "",
                           details: m.link.map(NetPresentation.facts) ?? [Fact(L10n.t("net.fact.interface"), m.iface), Fact(L10n.t("net.fact.localIP"), m.ip ?? "—")])
        net.ssidAccess = m.link.map { l in l.wifi == nil ? .notWiFi : l.wifi?.ssid != nil ? .known : m.ssidAccess } ?? .known
        net.perAppAvailable = m.perAppAvailable; net.perAppReady = m.perAppReady
        s.net = net
        let b = m.battery
        s.system = SystemState(chipTemp: 0, gpuTemp: 0, ssdTemp: 0, fanRPM: 0, thermal: m.thermal,
                               battery: Int((b?.percent ?? 0).rounded()), charging: b?.charging ?? false,
                               batteryDrain30m: incident?.kind == .battery ? m.batteryDrain30m : nil,   // slow drain is not a warning
                               watts: 0, adapter: b?.adapterText ?? "—", health: b?.healthText ?? "—", capacity: b?.capacityText ?? "—",
                               cycles: b?.cycles ?? 0, gpuPercent: 0, gpuCores: 0, onAC: b?.onAC ?? true, machine: m.machine)
        s.groups = m.groups
        s.docker = m.docker
        if let r = m.sensors {
            s.system.chipTemp = r.chipTemp; s.system.gpuTemp = r.gpuTemp ?? 0; s.system.ssdTemp = r.ssdTemp ?? 0
            s.system.fanRPM = r.fanRPM; s.system.fanCount = r.fanCount; s.system.fanMinRPM = r.fanMinRPM
            s.system.watts = r.systemWatts ?? 0; s.system.cpuWatts = r.cpuWatts; s.system.gpuWatts = r.gpuWatts
            s.system.gpuPercent = r.gpuPercent; s.system.gpuCores = r.gpuCores; s.system.gpuApps = Array(r.gpuApps.prefix(2))
        }
        s.incident = incident
        if let top = m.groups.filter({ $0.id != "sys:macos" }).max(by: { $0.cpuCores < $1.cpuCores }) {   // the aggregate system row is not an app
            s.calmTop = (top.name, Int((top.cpuCores / Double(max(1, m.coreCount)) * 100).rounded()))
        }
        s.suggestions = suggestions(m)
        return s
    }

    static func suggestions(_ m: LiveMeasurements) -> [Suggestion] {
        var out: [Suggestion] = []
        for g in m.groups where g.isOrphan {
            out.append(Suggestion(title: L10n.t("suggest.orphan.title", ["context": g.context.replacingOccurrences(of: " · :", with: " :")]),
                                  detail: L10n.t("suggest.orphan.detail", ["uptime": g.uptime]), target: .group(g.id)))
        }
        // The safe amount counts anonymous volumes and images only; named data volumes of stopped projects are not counted.
        let k = m.docker.disk, safe = k.volumesAnonReclaimGB + k.imagesReclaimGB
        if m.docker.running, safe >= 5 {
            out.append(Suggestion(title: L10n.t("headline.disk.dockerReclaim", ["gb": Fmt.dec1(safe)]),
                                  detail: L10n.plural("suggest.docker.volumes", k.volumesAnonUnusedCount)
                                      + (k.imagesUnusedCount > 0 ? L10n.plural("suggest.docker.images", k.imagesUnusedCount) : ""),
                                  target: .docker))
        }
        for f in m.downloads.sorted(by: { $0.gb > $1.gb }) {
            let size = f.gb >= 10 ? Fmt.int(f.gb) : Fmt.dec1(f.gb)
            out.append(Suggestion(title: L10n.t("suggest.downloads.title", ["size": size, "name": f.name]),
                                  detail: L10n.plural("suggest.downloads.detail", max(2, f.idleDays / 7)),
                                  target: .disk(["Downloads"])))
        }
        return out
    }
}
