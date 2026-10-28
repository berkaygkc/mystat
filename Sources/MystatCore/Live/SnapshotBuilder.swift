import Foundation

/// Bir örnekleme turunun ölçümleri (canlı kaynak doldurur, `SnapshotBuilder` anlam verir).
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

    public init(cpu: CPUState, memory: MemoryState, disk: DiskState, net: (down: Double, up: Double, todayDown: Double, todayUp: Double),
                iface: String, ip: String?, groups: [ProcessGroup], thermal: Level, battery: BatteryReading?, batteryDrain30m: Double?,
                machine: MachineInfo, downloads: [(name: String, gb: Double, idleDays: Int)], coreCount: Int, docker: DockerState = .notRunning) {
        self.docker = docker
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
        s.net = NetState(downMBps: m.net.down, upMBps: m.net.up, todayDownGB: m.net.todayDown, todayUpGB: m.net.todayUp, latencyMs: 0,
                         iface: m.iface, ssid: "", details: [Fact("Arayüz", m.iface), Fact("Yerel IP", m.ip ?? "—")])
        let b = m.battery
        s.system = SystemState(chipTemp: 0, gpuTemp: 0, ssdTemp: 0, fanRPM: 0, thermal: m.thermal,
                               battery: Int((b?.percent ?? 0).rounded()), charging: b?.charging ?? false,
                               batteryDrain30m: incident?.kind == .battery ? m.batteryDrain30m : nil,   // yavaş erime uyarı değil
                               watts: 0, adapter: b?.adapterText ?? "—", health: b?.healthText ?? "—", capacity: b?.capacityText ?? "—",
                               cycles: b?.cycles ?? 0, gpuPercent: 0, gpuCores: 0, onAC: b?.onAC ?? true, machine: m.machine)
        s.groups = m.groups
        s.docker = m.docker
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
