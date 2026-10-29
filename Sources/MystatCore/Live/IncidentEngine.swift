import Foundation

/// Olay motorunun bir turluk girdisi. Büyüme ve yazım toplamları grup geçmişinden gelir (Task 8 halkaları).
public struct IncidentInputs: Sendable {
    public var cpu: CPUState
    public var memory: MemoryState
    public var swapGrowing: Bool
    public var disk: DiskState
    public var groups: [ProcessGroup]
    public var thermal: Level
    /// Son 30 dk'daki pil erimesi (yüzde puan); pilde değilse ya da ölçülemiyorsa nil.
    public var batteryDrain30m: Double?
    public var onAC: Bool
    /// Grup id → son 10 dk'daki ayak izi büyümesi (GB).
    public var memoryGrowthGB: [String: Double]
    /// Grup id → son 1 saatte diske yazılan (GB).
    public var diskWrittenGB1h: [String: Double]
    /// Çalışan container'lar (Docker çalışmıyorsa boş).
    public var containers: [Container]

    public init(cpu: CPUState, memory: MemoryState, swapGrowing: Bool, disk: DiskState, groups: [ProcessGroup], thermal: Level,
                batteryDrain30m: Double?, onAC: Bool, memoryGrowthGB: [String: Double], diskWrittenGB1h: [String: Double],
                containers: [Container] = []) {
        self.containers = containers
        self.cpu = cpu; self.memory = memory; self.swapGrowing = swapGrowing; self.disk = disk; self.groups = groups
        self.thermal = thermal; self.batteryDrain30m = batteryDrain30m; self.onAC = onAC
        self.memoryGrowthGB = memoryGrowthGB; self.diskWrittenGB1h = diskWrittenGB1h
    }
}

/// Süreklilik süreli olaylar (spec §7.2, §7.2.1).
/// - Olay, koşul başladığında başlar (başlangıç saati o an); süre dolunca görünür.
/// - Koşul eşiğin altında 30 sn kalınca biter. Uzun aralıkta (uyku) bütün süreklilik sıfırlanır.
/// - Birden fazla olay varsa kritik, eşitlikte en eski öne çıkar.
public struct IncidentEngine: Sendable {
    static let calmToEnd: TimeInterval = 30

    private struct Since: Sendable { var warn: Date?; var crit: Date? }
    private struct Active: Sendable { var start: Date; var level: Level; var peak: Double; var clearSince: Date? }

    private var since: [IncidentKind: Since] = [:]
    private var groupSince: [String: Since] = [:]
    /// Container başına: yoğunluk (≥ %50, 120 sn) ve sorun (yeniden başlama/unhealthy, 30 sn) ayrı tutulur.
    private var busySince: [String: Since] = [:], troubleSince: [String: Since] = [:]
    /// Olay sürdükçe son sorumlular ve neden (sorun mu yoğunluk mu): koşul düzelince 30 sn'lik bitişte de aynı metin.
    private var dockerCulprits: (list: [Container], trouble: Bool)?
    private var active: [IncidentKind: Active] = [:]
    private var last: Date?

    public init() {}

    public mutating func update(_ i: IncidentInputs, at now: Date) -> Incident? {
        if let l = last, now.timeIntervalSince(l) > SampleGap.maxInterval { self = IncidentEngine() }
        last = now

        // Her tür: anlık seviye, süreklilik süresi, izlenen değer.
        let total = i.cpu.percent
        let cpuTotal = level(total >= 85, total >= 70)
        var groupLevel = Level.ok, groupSustained = Level.ok
        var seen = Set<String>()
        for g in i.groups {
            seen.insert(g.id)
            let l = level(g.cpuCores >= 4, g.cpuCores >= 2)
            groupLevel = max(groupLevel, l)
            groupSustained = max(groupSustained, sustain(&groupSince[g.id, default: Since()], l, now, after: 120))
        }
        groupSince = groupSince.filter { seen.contains($0.key) }
        let cpuSustained = max(sustain(&since[.cpu, default: Since()], cpuTotal, now, after: 60), groupSustained)
        step(.cpu, instant: max(cpuTotal, groupLevel), sustained: cpuSustained, metric: total, now)

        let mem: Level = i.memory.pressureLevel == .crit || i.swapGrowing ? .crit : i.memory.pressureLevel
        step(.memory, instant: mem, sustained: sustain(&since[.memory, default: Since()], mem, now, after: 30),
             metric: i.memory.pressurePercent, now)

        let disk = level(i.disk.freeGB < 10, i.disk.freeGB < 20)
        step(.disk, instant: disk, sustained: disk, metric: i.disk.percent, now)

        step(.heat, instant: i.thermal, sustained: sustain(&since[.heat, default: Since()], i.thermal, now, after: 30), metric: 0, now)

        let drain = i.onAC ? 0 : i.batteryDrain30m ?? 0
        let bat = level(drain > 35, drain > 20)
        step(.battery, instant: bat, sustained: bat, metric: drain, now)

        var dockerLevel = Level.ok, dockerSustained = Level.ok, dockerPeak = 0.0
        for c in i.containers {
            let trouble: Level = c.restarting || !c.healthy ? .crit : .ok, busy: Level = c.cpuPercent >= 50 ? .warn : .ok
            dockerLevel = max(dockerLevel, trouble, busy)
            dockerPeak = max(dockerPeak, c.cpuPercent)
            dockerSustained = max(dockerSustained, sustain(&troubleSince[c.id, default: Since()], trouble, now, after: 30),
                                  sustain(&busySince[c.id, default: Since()], busy, now, after: 120))
        }
        let ids = Set(i.containers.map(\.id))
        busySince = busySince.filter { ids.contains($0.key) }
        troubleSince = troubleSince.filter { ids.contains($0.key) }
        step(.docker, instant: dockerLevel, sustained: dockerSustained, metric: dockerPeak, now)
        if let a = active[.docker] {
            let bad = i.containers.filter { $0.restarting || !$0.healthy }
            let busy = i.containers.filter { $0.cpuPercent >= 50 }.sorted { $0.cpuPercent > $1.cpuPercent }
            if a.level == .crit, !bad.isEmpty { dockerCulprits = (Array(bad.prefix(3)), true) }
            else if !busy.isEmpty, a.level < .crit || dockerCulprits?.trouble != true { dockerCulprits = (Array(busy.prefix(3)), false) }
        } else {
            dockerCulprits = nil
        }

        guard let (kind, a) = active.sorted(by: { $0.value.level != $1.value.level ? $0.value.level > $1.value.level : $0.value.start < $1.value.start }).first
        else { return nil }
        return incident(kind, a, i, now)
    }

    // MARK: - Süreklilik

    private func level(_ crit: Bool, _ warn: Bool) -> Level { crit ? .crit : warn ? .warn : .ok }

    /// Anlık seviye en az `after` sn sürdüyse o seviye; değilse daha düşük süreklilik.
    private func sustain(_ s: inout Since, _ l: Level, _ now: Date, after: TimeInterval) -> Level {
        s.warn = l >= .warn ? (s.warn ?? now) : nil
        s.crit = l >= .crit ? (s.crit ?? now) : nil
        if let c = s.crit, now.timeIntervalSince(c) >= after { return .crit }
        if let w = s.warn, now.timeIntervalSince(w) >= after { return .warn }
        return .ok
    }

    private mutating func step(_ k: IncidentKind, instant: Level, sustained: Level, metric: Double, _ now: Date) {
        if var a = active[k] {
            if instant >= .warn {
                a.clearSince = nil
                a.level = max(instant, sustained)
                a.peak = max(a.peak, metric)
            } else {
                a.clearSince = a.clearSince ?? now
                if now.timeIntervalSince(a.clearSince!) >= Self.calmToEnd { active[k] = nil; return }
            }
            active[k] = a
        } else if sustained >= .warn {
            let onset = switch k {
            case .cpu: ([since[.cpu]?.warn] + groupSince.values.map(\.warn)).compactMap { $0 }.min()
            case .docker: (busySince.values.map(\.warn) + troubleSince.values.map(\.crit)).compactMap { $0 }.min()
            default: since[k]?.warn
            }
            active[k] = Active(start: onset ?? now, level: sustained, peak: metric)
        }
    }

    // MARK: - Olay içeriği (§7.2.1)

    private func incident(_ k: IncidentKind, _ a: Active, _ i: IncidentInputs, _ now: Date) -> Incident {
        let started = Fmt.timeLine(a.start).prefix(5).description
        let byCPU = i.groups.filter { $0.cpuCores >= 0.1 }.sorted { $0.cpuCores > $1.cpuCores }.prefix(3)
        func top(_ d: [String: Double], _ n: Int, min: Double) -> [(String, Double)] {
            d.filter { $0.value >= min }.sorted { $0.value > $1.value }.prefix(n).map { ($0.key, $0.value) }
        }
        let ids: [String], values: [String], unit: String, facts: [Fact]
        switch k {
        case .cpu:
            ids = byCPU.map(\.id); values = byCPU.map { Fmt.dec1($0.cpuCores) }; unit = "çekirdek"
            facts = [Fact("Başladı", started), Fact("Zirve", Fmt.pct(a.peak)), Fact("Şu an", Fmt.pct(i.cpu.percent)),
                     Fact("Isı", i.thermal.thermalWord.lowercased(with: Fmt.locale), level: i.thermal)]
        case .memory:
            let t = top(i.memoryGrowthGB, 3, min: 0.1)
            ids = t.map(\.0); values = t.map { "+" + Fmt.dec1($0.1) }; unit = "GB"
            let word = switch i.memory.pressureLevel { case .ok: "düşük"; case .warn: "orta"; case .crit: "yüksek" }
            facts = [Fact("Baskı", word), Fact("Swap", Fmt.dec1(i.memory.swapGB) + " GB"), Fact("Sıkıştırılmış", Fmt.dec1(i.memory.compressed) + " GB")]
        case .disk:
            let t = top(i.diskWrittenGB1h, 2, min: 0.1)
            ids = t.map(\.0); values = t.map { $0.1 >= 10 ? Fmt.int($0.1) : Fmt.dec1($0.1) }; unit = "GB yazdı"
            facts = [Fact("Boş alan", Fmt.int(i.disk.freeGB) + " GB"), Fact("Sistemin boşaltabileceği", Fmt.int(i.disk.purgeableGB) + " GB")]
        case .docker:
            let shown = dockerCulprits?.list ?? [], trouble = dockerCulprits?.trouble ?? false
            ids = shown.map(\.name)
            values = shown.map { trouble ? ($0.restarting ? "yeniden başlıyor" : "sağlıksız") : Fmt.pct($0.cpuPercent) }
            unit = trouble ? "" : "CPU"
            let first = shown.first
            let health = first.map { $0.restarting ? "yeniden başlıyor" : $0.healthy ? "sağlıklı" : "sağlıksız" } ?? "sağlıklı"
            facts = [Fact("Proje", first.map { $0.project.isEmpty ? "—" : $0.project } ?? "—"),
                     Fact("Süre", "\(Int(now.timeIntervalSince(a.start) / 60)) dk"), Fact("Sağlık", health)]
        case .heat, .battery:
            // §7.2.1: enerji tüketen gruplar (W); süreç enerjisi okunamıyorsa CPU'ya göre.
            let byWatts = i.groups.filter { $0.watts >= 0.1 }.sorted { $0.watts > $1.watts }.prefix(3)
            if byWatts.isEmpty { ids = byCPU.map(\.id); values = byCPU.map { Fmt.dec1($0.cpuCores) }; unit = "çekirdek" }
            else { ids = byWatts.map(\.id); values = byWatts.map { Fmt.dec1($0.watts) }; unit = "W" }
            facts = k == .battery ? [Fact("Erime", "30 dk'da " + Fmt.pct(a.peak)), Fact("Şarj", "prizde değil")]
                                  : [Fact("Durum", i.thermal.thermalWord.lowercased(with: Fmt.locale), level: i.thermal), Fact("Başladı", started)]
        }
        return Incident(kind: k, level: a.level, startedAt: started, minutes: Int(now.timeIntervalSince(a.start) / 60),
                        peakPercent: a.peak, culpritIDs: ids, culpritValues: values, culpritUnit: unit, facts: facts)
    }
}
