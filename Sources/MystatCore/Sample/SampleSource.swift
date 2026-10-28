import Foundation
import Observation

/// Faz 1'in örnek veri kaynağı. Değerler ve seriler mockup'takiyle aynı formüllerle üretilir.
@MainActor
@Observable
public final class SampleSource: MetricsSource {
    public private(set) var snapshot: Snapshot
    @ObservationIgnored public let diskTree: DiskTree

    @ObservationIgnored private var isIncident: Bool
    @ObservationIgnored private var kind: IncidentKind
    @ObservationIgnored private var liveCPU: Double = 14
    @ObservationIgnored private var liveDown: Double = 14.6
    @ObservationIgnored private var rng: Mulberry32
    @ObservationIgnored private var cache: [CacheKey: [Double]] = [:]

    private struct CacheKey: Hashable { let key: SeriesKey; let range: TimeRange }

    public init(seed: UInt64 = 1, incident: Bool = false, kind: IncidentKind = .cpu) {
        isIncident = incident
        self.kind = kind
        rng = Mulberry32(seed: UInt32(truncatingIfNeeded: seed))
        diskTree = DiskTree(root: SampleData.makeTree())
        snapshot = Self.placeholder
        resetLive()
    }

    public var incident: Bool {
        get { isIncident }
        set { isIncident = newValue; resetLive() }
    }

    public var incidentKind: IncidentKind {
        get { kind }
        set { kind = newValue; resetLive() }
    }

    /// 2 sn'de bir çağrılır; mockup'taki `tickLive`.
    public func tick() {
        let target = cpuTarget
        liveCPU = min(98, max(3, liveCPU + (target - liveCPU) * 0.4 + (rng.next() - 0.5) * (target > 50 ? 6 : 5)))
        liveDown = min(19, max(10, liveDown + (rng.next() - 0.5) * 1.6))
        snapshot = build()
    }

    // MARK: - Durum

    private var loadIncident: Bool { isIncident && (kind == .cpu || kind == .heat) }
    private var cpuTarget: Double { isIncident && kind == .cpu ? 91 : isIncident && kind == .heat ? 64 : 14 }

    private func resetLive() {
        liveCPU = cpuTarget
        liveDown = 14.6
        cache.removeAll()
        snapshot = build()
    }

    private func build() -> Snapshot {
        let inc = isIncident, cpuInc = inc && kind == .cpu, load = loadIncident
        let memInc = inc && kind == .memory, diskInc = inc && kind == .disk
        let heat = inc && (kind == .heat || kind == .cpu), bat = inc && kind == .battery

        let groups = SampleData.groups.map { g in
            var mem = g.ram
            if memInc && g.id == "docker" { mem += 2.1 }
            if memInc && g.id == "next-web" { mem += 1.4 }
            return ProcessGroup(
                id: g.id, name: g.name, context: g.ctx,
                cpuCores: load ? g.cpu.1 : g.cpu.0, memoryGB: mem, netMBps: cpuInc ? g.net.1 : g.net.0,
                uptime: g.up, processCount: g.n, folder: g.dir, terminal: g.term, port: g.port,
                isOrphan: g.orphan, relatedID: g.related, isDocker: g.docker,
                children: g.kids.map { ChildProcess(name: $0.0, cpuCores: load ? $0.2 : $0.1) })
        }
        let containers = SampleData.containers.map { c in
            let cpu = cpuInc ? c.2.1 : (inc && kind == .docker && c.0 == "acmecorp-verifier") ? 62 : c.2.0
            return Container(name: c.0, image: c.1, cpuPercent: cpu, memoryMB: c.3, healthy: true, uptime: "45 sa")
        }
        var coreRNG = Mulberry32(seed: 77)
        let cores = (0..<14).map { i in
            let r = coreRNG.next()
            return load ? (i < 10 ? 80 + r * 18 : 60 + r * 30) : (i < 10 ? 4 + r * 18 : 8 + r * 20)
        }
        let write = series(.diskWrite, range: .m10).last ?? 0, read = series(.diskRead, range: .m10).last ?? 0

        return Snapshot(
            cpu: CPUState(percent: liveCPU, systemPercent: liveCPU * 0.22, cores: cores,
                          loadAvg: load ? [12.4, 9.8, 6.1] : [2.1, 2.4, 2.6]),
            memory: MemoryState(percent: memInc ? 86 : cpuInc ? 81 : 78, usedGB: memInc ? 41.3 : cpuInc ? 38.9 : 37.6, totalGB: 48,
                                apps: 18.8, wired: 5.6, compressed: memInc ? 18.9 : 14.4, free: memInc ? 4.7 : 9.2,
                                pressurePercent: memInc ? 78 : cpuInc ? 44 : 41, pressureLevel: memInc ? .crit : .ok,
                                swapGB: memInc ? 3.2 : 0),
            disk: DiskState(percent: diskInc ? 98 : 62, freeGB: diskInc ? 8 : 175, usedGB: diskInc ? 452 : 285,
                            purgeableGB: 12, readMBps: read, writeMBps: write),
            net: NetState(downMBps: liveDown, upMBps: liveDown * 0.13, todayDownGB: 12.4, todayUpGB: 1.8, latencyMs: 18,
                          iface: "Wi‑Fi", ssid: "Ev", details: SampleData.netDetails),
            docker: DockerState(project: "deploy", containers: containers, vmMemoryGB: 10.2, vmCores: 8,
                                disk: DockerDisk(imagesGB: 8.8, imagesReclaimGB: 2.8, imagesCount: 21,
                                                 volumesGB: 16.9, volumesReclaimGB: 12.6, volumesCount: 192,
                                                 buildCacheGB: 0, rawGB: 27)),
            system: SystemState(chipTemp: heat ? 91 : 48, gpuTemp: heat ? 63 : 41, ssdTemp: 38, fanRPM: heat ? 4800 : 0,
                                thermal: heat ? .warn : .ok, battery: bat ? 62 : 100, charging: !bat, batteryDrain30m: bat ? 25 : nil,
                                watts: bat ? 38 : load ? 78 : 14, adapter: "140 W USB‑C", health: "%91 · iyi",
                                capacity: "7.819 / 8.579 mAh", cycles: 75, gpuPercent: load ? 18 : 6, gpuCores: 20),
            groups: groups,
            incident: inc ? makeIncident() : nil,
            suggestions: [
                Suggestion(title: "acmecorp/web :3011 sahipsiz çalışıyor", detail: "Başlatan terminal kapanmış · 14 dk", target: .group("next-web")),
                Suggestion(title: "Docker'da 12,6 GB geri kazanılabilir", detail: "177 kullanılmayan volume", target: .docker),
                Suggestion(title: "İndirilenler'de 9,5 GB'lık Xcode arşivi", detail: "3 haftadır açılmamış", target: .disk(["Downloads"])),
            ],
            calmTop: ("Brave Browser", 8))
    }

    private func makeIncident() -> Incident {
        switch kind {
        case .cpu:
            return Incident(kind: .cpu, level: .crit, startedAt: "08:41", minutes: 4, peakPercent: 97,
                            culpritIDs: ["claude-acmecorp", "next-web", "docker"], culpritValues: ["4,2", "3,1", "0,9"], culpritUnit: "çekirdek",
                            facts: [Fact("Başladı", "08:41"), Fact("Zirve", "%97"), Fact("Şu an", Fmt.pct(liveCPU)), Fact("Isı", "91°")])
        case .memory:
            return Incident(kind: .memory, level: .crit, startedAt: "09:12", minutes: 6, peakPercent: 86,
                            culpritIDs: ["docker", "next-web"], culpritValues: ["+2,1", "+1,4"], culpritUnit: "GB",
                            facts: [Fact("Baskı", "yüksek"), Fact("Swap", "3,2 GB"), Fact("Sıkıştırılmış", "18,9 GB")])
        case .disk:
            return Incident(kind: .disk, level: .crit, startedAt: "07:55", minutes: 35, peakPercent: 98,
                            culpritIDs: ["docker", "next-web"], culpritValues: ["12", "3,1"], culpritUnit: "GB yazdı",
                            facts: [Fact("Boş alan", "8 GB"), Fact("Son 24 sa", "−14 GB"), Fact("Docker'da geri kazanılabilir", "12,6 GB")])
        case .docker:
            return Incident(kind: .docker, level: .warn, startedAt: "09:24", minutes: 6, peakPercent: 62,
                            culpritIDs: ["acmecorp-verifier"], culpritValues: ["%62"], culpritUnit: "CPU",
                            facts: [Fact("Proje", "deploy"), Fact("Süre", "6 dk"), Fact("Sağlık", "sağlıklı")])
        case .heat:
            return Incident(kind: .heat, level: .warn, startedAt: "09:02", minutes: 9, peakPercent: 91,
                            culpritIDs: ["claude-acmecorp", "next-web", "docker"], culpritValues: ["26", "19", "6"], culpritUnit: "W",
                            facts: [Fact("Sıcaklık", "91°"), Fact("Fan", "4.800 dev/dk"), Fact("Durum", "ılık")])
        case .battery:
            return Incident(kind: .battery, level: .warn, startedAt: "08:58", minutes: 30, peakPercent: 25,
                            culpritIDs: ["claude-acmecorp", "next-web", "brave"], culpritValues: ["14", "11", "6"], culpritUnit: "W",
                            facts: [Fact("Erime", "30 dk'da %25"), Fact("Kalan", "1 sa 10 dk"), Fact("Şarj", "prizde değil")])
        }
    }

    // MARK: - Seriler (mockup'taki `series`)

    public func series(_ key: SeriesKey, range: TimeRange) -> [Double] {
        let ck = CacheKey(key: key, range: range)
        if let hit = cache[ck] { return hit }
        let out = makeSeries(key, range)
        cache[ck] = out
        return out
    }

    private func makeSeries(_ key: SeriesKey, _ range: TimeRange) -> [Double] {
        let n = range.pointCount
        let s: UInt32 = switch range { case .m10: 1; case .h1: 2; case .h24: 3; case .d7: 4 }
        let tail: Int = switch range { case .m10: 48; case .h1: 8; case .h24: 2; case .d7: 1 }
        let inc = isIncident
        let on = { (k: IncidentKind) in inc && self.kind == k }
        func up(_ a: [Double], _ lo: Double, _ hi: Double, _ seed: UInt32, when: Bool) -> [Double] { when ? surge(a, tail, lo, hi, seed) : a }

        switch key {
        case .cpu:
            let heat = on(.heat)
            let lo: Double = heat ? 55 : 86, hi: Double = heat ? 70 : 96
            return up(walk(11 * s, n, 15, 9), lo, hi, 5, when: on(.cpu) || heat)
        case .cpuSystem: return up(walk(13 * s, n, 5, 3), 14, 19, 6, when: on(.cpu))
        case .memUsed:
            let mem = on(.memory)
            let lo: Double = mem ? 84 : 80, hi: Double = mem ? 88 : 82
            return up(walk(17 * s, n, 78, 2.2, smooth: 0.9), lo, hi, 7, when: on(.cpu) || mem)
        case .memPressure:
            let mem = on(.memory)
            let lo: Double = mem ? 72 : 42, hi: Double = mem ? 82 : 46
            return up(walk(19 * s, n, 39, 4, smooth: 0.85), lo, hi, 8, when: on(.cpu) || mem)
        case .netDown: return walk(23 * s, n, 14, 4, smooth: 0.6, lo: 0.1, hi: 40)
        case .netUp: return walk(29 * s, n, 1.8, 0.8, smooth: 0.6, lo: 0, hi: 10)
        case .diskRead: return walk(31 * s, n, 8, 10, smooth: 0.55, lo: 0, hi: 400)
        case .diskWrite: return up(walk(37 * s, n, 14, 14, smooth: 0.55, lo: 0, hi: 400), 40, 80, 9, when: on(.cpu) || on(.disk))
        case .temp: return up(walk(41 * s, n, 48, 3, smooth: 0.85, lo: 30, hi: 105), 88, 93, 10, when: on(.cpu) || on(.heat))
        case .fan: return up(walk(43 * s, n, 0, 0, smooth: 0.85, lo: 0, hi: 7000), 4500, 4900, 11, when: on(.cpu) || on(.heat))
        case .power:
            let bat = on(.battery)
            let lo: Double = bat ? 30 : 72, hi: Double = bat ? 42 : 84
            return up(walk(47 * s, n, 14, 4, smooth: 0.7, lo: 2, hi: 140), lo, hi, 12, when: on(.cpu) || on(.heat) || bat)
        case .gpu: return up(walk(53 * s, n, 6, 4, smooth: 0.7), 15, 22, 13, when: on(.cpu))
        case .battery:
            let draining = on(.battery), count = Double(n)
            return (0..<n).map { i -> Double in
                let x = Double(i)
                return draining ? max(0, 100 - x * (38 / count)) : min(100, 72 + x * (40 / count))
            }
        case .dockerCPU:
            let dk = on(.docker)
            let lo: Double = dk ? 55 : 88, hi: Double = dk ? 70 : 99
            return up(walk(59 * s, n, 3, 2, smooth: 0.7), lo, hi, 14, when: on(.cpu) || dk)
        case .dockerTrend30:
            return (0..<30).map { i -> Double in
                let x = Double(i)
                let bump: Double = i > 22 ? 1.2 : 0
                return 18 + x * 0.3 + sin(x / 2.5) * 0.6 + bump
            }
        case .group(let id):
            guard let g = SampleData.groups.first(where: { $0.id == id }) else { return Array(repeating: 0, count: n) }
            let base = g.cpu.0 * 100 / 14, hot = g.cpu.1 * 100 / 14
            let seed = UInt32(("g:" + id).count * 7) + s
            return up(walk(seed, n, base, base * 0.5 + 0.5, smooth: 0.7), hot * 0.92, hot * 1.06, 15, when: loadIncident)
        }
    }

    private static let placeholder = Snapshot(
        cpu: CPUState(percent: 0, systemPercent: 0, cores: [], loadAvg: []),
        memory: MemoryState(percent: 0, usedGB: 0, totalGB: 48, apps: 0, wired: 0, compressed: 0, free: 0, pressurePercent: 0, pressureLevel: .ok, swapGB: 0),
        disk: DiskState(percent: 0, freeGB: 0, usedGB: 0, purgeableGB: 0, readMBps: 0, writeMBps: 0),
        net: NetState(downMBps: 0, upMBps: 0, todayDownGB: 0, todayUpGB: 0, latencyMs: 0, iface: "", ssid: "", details: []),
        docker: DockerState(project: "", containers: [], vmMemoryGB: 0, vmCores: 0,
                            disk: DockerDisk(imagesGB: 0, imagesReclaimGB: 0, imagesCount: 0, volumesGB: 0, volumesReclaimGB: 0, volumesCount: 0, buildCacheGB: 0, rawGB: 0)),
        system: SystemState(chipTemp: 0, gpuTemp: 0, ssdTemp: 0, fanRPM: 0, thermal: .ok, battery: 0, charging: true, batteryDrain30m: nil,
                            watts: 0, adapter: "", health: "", capacity: "", cycles: 0, gpuPercent: 0, gpuCores: 0),
        groups: [], incident: nil, suggestions: [], calmTop: ("", 0))
}
