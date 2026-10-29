import Foundation

/// Bir örnekleme turunun ölçümleri (canlı kaynak doldurur, `SnapshotBuilder` anlam verir).
/// Bir sensör turunun özeti (çip, fan ve sistem gücü her zaman; GPU sıcaklığı, IOReport ve GPU uygulamaları ilgi varken).
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
    /// İndirilenler'deki büyük ve eski dosyalar (≥ 2 GB, ≥ 14 gün açılmamış).
    public var downloads: [(name: String, gb: Double, idleDays: Int)]
    public var coreCount: Int
    public var docker: DockerState
    /// Sensör yoksa nil: Sistem bölümü Faz 2a'nın sakin durumunu gösterir.
    public var sensors: SensorReading?
    /// Ağ bölümü açıkken: birincil bağlantı, yönlendirici gecikmesi, uygulama bazında ağın okunabilirliği (2e).
    public var link: NetLink? = nil
    public var latencyMs: Double? = nil
    public var perAppAvailable = true
    public var perAppReady = true
    /// Wi‑Fi ağının adı yoksa konum izninin durumu.
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

/// Ölçümlerden arayüzün gördüğü Snapshot: sakin başlığın en yoğun grubu, öneriler (spec §7.3), ağ ve sistem olguları.
public enum SnapshotBuilder {
    public static func build(_ m: LiveMeasurements, incident: Incident?, capabilities: SourceCapabilities) -> Snapshot {
        var s = Snapshot.empty(capabilities: capabilities)
        s.cpu = m.cpu
        // Apple Silicon'da mantıksal CPU'ların başı verimlilik kümesi (ioreg cluster-type); arayüz performansı önce gösterir.
        let e = m.machine.eCores
        if e > 0, m.machine.pCores + e == m.cpu.cores.count { s.cpu.cores = Array(m.cpu.cores[e...] + m.cpu.cores[..<e]) }
        s.memory = m.memory
        s.disk = m.disk
        var net = NetState(downMBps: m.net.down, upMBps: m.net.up, todayDownGB: m.net.todayDown, todayUpGB: m.net.todayUp,
                           latencyMs: m.latencyMs ?? .nan, iface: m.link?.displayName ?? m.iface, ssid: m.link?.wifi?.ssid ?? "",
                           details: m.link.map(NetPresentation.facts) ?? [Fact("Arayüz", m.iface), Fact("Yerel IP", m.ip ?? "—")])
        net.ssidAccess = m.link.map { l in l.wifi == nil ? .notWiFi : l.wifi?.ssid != nil ? .known : m.ssidAccess } ?? .known
        net.perAppAvailable = m.perAppAvailable; net.perAppReady = m.perAppReady
        s.net = net
        let b = m.battery
        s.system = SystemState(chipTemp: 0, gpuTemp: 0, ssdTemp: 0, fanRPM: 0, thermal: m.thermal,
                               battery: Int((b?.percent ?? 0).rounded()), charging: b?.charging ?? false,
                               batteryDrain30m: incident?.kind == .battery ? m.batteryDrain30m : nil,   // yavaş erime uyarı değil
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
        if let top = m.groups.filter({ $0.id != "sys:macos" }).max(by: { $0.cpuCores < $1.cpuCores }) {   // toplu sistem satırı uygulama değil
            s.calmTop = (top.name, Int((top.cpuCores / Double(max(1, m.coreCount)) * 100).rounded()))
        }
        s.suggestions = suggestions(m)
        return s
    }

    static func suggestions(_ m: LiveMeasurements) -> [Suggestion] {
        var out: [Suggestion] = []
        for g in m.groups where g.isOrphan {
            out.append(Suggestion(title: "\(g.context.replacingOccurrences(of: " · :", with: " :")) sahipsiz çalışıyor",
                                  detail: "Başlatan terminal kapanmış · \(g.uptime)", target: .group(g.id)))
        }
        // Kullanıcının kararı: güvenli miktar (adsız volume + image); durmuş projelerin adlı veri volume'leri sayılmaz.
        let k = m.docker.disk, safe = k.volumesAnonReclaimGB + k.imagesReclaimGB
        if m.docker.running, safe >= 5 {
            out.append(Suggestion(title: "Docker'da \(Fmt.dec1(safe)) GB geri kazanılabilir",
                                  detail: "\(k.volumesAnonUnusedCount) adsız volume" + (k.imagesUnusedCount > 0 ? " · \(k.imagesUnusedCount) image" : ""),
                                  target: .docker))
        }
        for f in m.downloads.sorted(by: { $0.gb > $1.gb }) {
            let size = f.gb >= 10 ? Fmt.int(f.gb) : Fmt.dec1(f.gb)
            out.append(Suggestion(title: "İndirilenler'de \(size) GB'lık \(f.name)", detail: "\(max(2, f.idleDays / 7)) haftadır açılmamış",
                                  target: .disk(["Downloads"])))
        }
        return out
    }
}
