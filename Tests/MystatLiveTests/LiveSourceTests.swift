import Foundation
import MystatCore
import MystatProbes
import Synchronization
import Testing
@testable import MystatLive

/// Senaryolu sahte sistem: her çağrıda sayaçlar `step` kadar ilerler.
final class FakeProbe: SystemProbe {
    let calls = Mutex<[String: Int]>([:])
    let step = Mutex(0)
    let busyCores: Double
    /// pid 100'ün başlangıcı; değişirse pid başka bir sürece geçmiş demektir.
    let start100 = Mutex(Date(timeIntervalSince1970: 1_793_000_000))
    /// Ek kendi süreçleri (başka gruplar).
    let extra = Mutex<[ProcessRecord]>([])

    init(busyCores: Double = 0) { self.busyCores = busyCores }

    func count(_ k: String) { calls.withLock { $0[k, default: 0] += 1 } }
    func n(_ k: String) -> Int { calls.withLock { $0[k] ?? 0 } }
    func advance() { step.withLock { $0 += 1 } }
    var s: UInt64 { UInt64(step.withLock { $0 }) }

    // 2 çekirdek; her adımda çekirdek 0: 80/100 meşgul (60 kullanıcı + 20 sistem), çekirdek 1: 50/100.
    func coreTicks() -> [CoreTicks] {
        [CoreTicks(user: 60 * s, system: 20 * s, idle: 20 * s, nice: 0), CoreTicks(user: 50 * s, system: 0, idle: 50 * s, nice: 0)]
    }
    func vm() -> VMCounters {
        VMCounters(pageSize: 16384, total: 48 << 30, free: 100_000, active: 0, inactive: 0, speculative: 0, wired: 200_000,
                   compressor: 300_000, purgeable: 50_000, internal: 1_250_000, external: 400_000, swapUsed: 0, pressureLevel: 1, memoryLevel: 59)
    }
    func loadAverage() -> [Double] { [2.1, 2.4, 2.6] }
    func interfaces() -> [InterfaceCounters] { [InterfaceCounters(name: "en0", rx: 4_800_000 * s, tx: 600_000 * s, up: true)] }
    func primaryInterface() -> String? { "en0" }
    func localIPv4(of iface: String) -> String? { "192.168.1.122" }
    func dataVolume() -> VolumeCapacity { VolumeCapacity(total: 500_000_000_000, available: 175_000_000_000, availableImportant: 187_000_000_000) }
    func diskIO() -> DiskIOCounters { DiskIOCounters(bytesRead: 16_400_000 * s, bytesWritten: 9_400_000 * s) }
    func processes() -> [ProcessRecord] {
        count("processes")
        let start = start100.withLock { $0 }
        return [ProcessRecord(pid: 100, ppid: 1, uid: 501, name: "claude", path: "/Users/u/.local/bin/claude", args: ["claude"],
                              cwd: "/Users/u/acmecorp", start: start, hasTTY: true,
                              cpuTime: UInt64(busyCores * 2e9) * s, footprint: 1 << 30, energy: 0, diskWritten: 1_000_000 * s),
                ProcessRecord(pid: 1, ppid: 0, uid: 0, name: "launchd", path: "/sbin/launchd", args: [], cwd: nil, start: .distantPast,
                              hasTTY: false, cpuTime: 0, footprint: 0, energy: 0, diskWritten: 0, restricted: true)] + extra.withLock { $0 }
    }
    func listeningPorts(pids: [Int32]) -> [Int32: [Int]] { count("ports"); return [:] }
    func thermal() -> Level { .ok }
    func battery() -> BatteryReading? {
        BatteryReading(percent: 100, charging: false, onAC: true, adapterWatts: 65, adapterUSBC: true, cycles: 75, designCapacity: 8579, maxCapacity: 7787)
    }
    func machine() -> MachineInfo { MachineInfo(model: "MacBook Pro", chip: "M4 Pro", pCores: 1, eCores: 1, memoryGB: 48, boot: .now) }
    func largeOldDownloads(now: Date) -> [(name: String, gb: Double, idleDays: Int)] { count("downloads"); return [] }
}

@MainActor @Suite struct LiveSourceTests {
    let t0 = Date(timeIntervalSince1970: 1_793_163_600)

    func source(_ p: FakeProbe) -> LiveSource { LiveSource(probe: p, historyURL: nil, persistToday: false, autostart: false, dockerAPI: FakeDockerAPI()) }

    func tick(_ s: LiveSource, _ p: FakeProbe, _ seconds: Double) async {
        p.advance()
        await s.step(at: t0.addingTimeInterval(seconds))
    }

    @Test func publishesRealNumbersAfterTwoSamples() async {
        let p = FakeProbe(), s = source(p)
        await tick(s, p, 0)
        await tick(s, p, 2)
        #expect(abs(s.snapshot.cpu.percent - 65) < 0.01)
        #expect(s.snapshot.cpu.loadAvg == [2.1, 2.4, 2.6])
        #expect(abs(s.snapshot.memory.percent - Double(1_700_000 * 16384) / Double(48 << 30) * 100) < 0.01)
        #expect(abs(s.snapshot.net.downMBps - 2.4) < 1e-9 && abs(s.snapshot.disk.readMBps - 8.2) < 1e-9)
        #expect(abs(s.snapshot.disk.percent - 62.6) < 1e-9)
        #expect(s.snapshot.system.machine?.chip == "M4 Pro" && s.snapshot.system.battery == 100)
        #expect(s.series(.cpu, range: .m10).last.map { abs($0 - 65) < 0.01 } == true)
        #expect(s.snapshot.capabilities == LiveSource.capabilities)
    }

    @Test func detailInterestChangesProcessCadence() async {
        let p = FakeProbe(), s = source(p)
        for t in stride(from: 0.0, through: 6, by: 2) { await tick(s, p, t) }
        #expect(p.n("processes") == 2)                  // 0 ve 6 sn (kapalıyken 5 sn)
        #expect(p.n("ports") == 0)                      // hafif mod: port okunmaz
        s.setDetailInterest(true)
        for t in stride(from: 8.0, through: 14, by: 2) { await tick(s, p, t) }
        #expect(p.n("processes") == 6)                  // açıkken her tur
    }

    @Test func groupsAndResidualSystemRow() async {
        let p = FakeProbe(busyCores: 1.2), s = source(p)
        s.setDetailInterest(true)
        await tick(s, p, 0)
        await tick(s, p, 2)
        let claude = s.snapshot.groups.first { $0.name == "Claude Code" }
        #expect(claude.map { abs($0.cpuCores - 1.2) < 0.01 } == true)
        #expect(claude?.pids == [100])
        // toplam %65 × 2 çekirdek = 1,3 çekirdek; Claude 1,2 → kalan 0,1 "macOS" satırında
        let mac = s.snapshot.groups.first { $0.id == "sys:macos" }
        #expect(mac.map { abs($0.cpuCores - 0.1) < 0.01 } == true)
        #expect(s.series(.group(claude!.id), range: .m10).last.map { abs($0 - 1.2) < 0.01 } == true)
    }

    @Test func sustainedLoadBecomesIncident() async {
        let p = FakeProbe(busyCores: 1.3), s = source(p)   // tek grup ≥ 2 değil; toplam %65 < %70
        for t in stride(from: 0.0, through: 130, by: 2) { await tick(s, p, t) }
        #expect(s.snapshot.incident == nil)
        let q = FakeProbe(busyCores: 4.5), h = source(q)   // tek grup ≥ 4 çekirdek, 2 dk
        h.setDetailInterest(true)
        for t in stride(from: 0.0, through: 126, by: 2) { await tick(h, q, t) }
        #expect(h.snapshot.incident?.kind == .cpu && h.snapshot.incident?.level == .crit)
    }

    /// Sinyal, grubun o anki listede hâlâ aynı süreç olan üyelerine gider (Review Focus #2).
    @Test func stopResolvesCurrentMembers() async {
        let p = FakeProbe(busyCores: 1), s = source(p)
        var sent: [([Int32], Bool)] = []
        s.signaler = { pids, force in sent.append((pids, force)); return .done(count: pids.count) }
        s.setDetailInterest(true)
        await tick(s, p, 0)
        await tick(s, p, 2)
        let id = s.snapshot.groups.first { $0.name == "Claude Code" }!.id
        #expect(s.stop(groupID: id, pids: [100], force: true) == .done(count: 1))
        #expect(sent.count == 1 && sent[0].0 == [100] && sent[0].1)
        p.start100.withLock { $0 = $0.addingTimeInterval(5) }   // pid 100 artık başka süreç
        #expect(s.stop(groupID: id, pids: [100], force: false) == .notFound)
        #expect(sent.count == 1)
        #expect(s.stop(groupID: "yok", pids: [100], force: false) == .notFound)
    }

    @Test func stopRefusesSystemGroup() async {
        let p = FakeProbe(busyCores: 1), s = source(p)
        var called = false
        s.signaler = { _, _ in called = true; return .done(count: 1) }
        s.setDetailInterest(true)
        await tick(s, p, 0)
        await tick(s, p, 2)
        #expect(s.stop(groupID: "sys:macos", pids: [], force: true) == .notPermitted(reason: StopOutcome.foreignReason))
        #expect(!called)
    }

    /// `--log-values` satırı: tools/consistency.sh bunu top ve vm_stat ile yan yana yazar.
    @Test func logLineCarriesComparableValues() async {
        let p = FakeProbe(), s = source(p)
        await tick(s, p, 0)
        await tick(s, p, 2)
        let line = LiveSource.logLine(s.snapshot)
        #expect(line.hasPrefix("mystat cpu=65.0 user=55.0 sys=10.0 mem=54.0 "))
        #expect(line.contains(" memGB=") && line.contains(" down=2.40 up=0.30"))
        var d = SampleSource(seed: 1).snapshot
        d.docker.containers = Array(d.docker.containers.prefix(2))
        let dl = LiveSource.logLine(d)                                   // tools/docker-check.sh bunları docker CLI ile karşılaştırır
        #expect(dl.contains(" containers=2 ") && dl.contains(" dockerCPU=") && dl.contains(" dockerMem="))
        #expect(dl.hasSuffix(" imgReclaim=2.80 volReclaim=12.60 volAnon=7.10"))
    }

    /// Onay penceresi açıkken grubun kimliği başka oturuma geçebilir (aynı klasörde iki oturum, biri bitti):
    /// sinyal yalnızca pencere açıldığındaki üyelerden hâlâ grupta olanlara gider.
    @Test func stopOnlyHitsMembersFromConfirmTime() async {
        let p = FakeProbe(busyCores: 1), s = source(p)
        var sent: [[Int32]] = []
        s.signaler = { pids, _ in sent.append(pids); return .done(count: pids.count) }
        s.setDetailInterest(true)
        await tick(s, p, 0)
        await tick(s, p, 2)
        let g = s.snapshot.groups.first { $0.name == "Claude Code" }!
        #expect(s.stop(groupID: g.id, pids: [999], force: false) == .notFound)
        // pencere açıldığında gruptaydı, şimdi yaşıyor ama başka grupta (ör. kimliği devralınan oturum)
        p.extra.withLock { $0 = [ProcessRecord(pid: 300, ppid: 1, uid: 501, name: "node", path: "/opt/homebrew/bin/node", args: ["node", "x.js"],
                                               cwd: "/tmp", start: Date(timeIntervalSince1970: 1_793_000_000), hasTTY: false, cpuTime: 0,
                                               footprint: 1 << 20, energy: 0, diskWritten: 0)] }
        await tick(s, p, 4)
        #expect(s.stop(groupID: g.id, pids: [300], force: false) == .notFound)
        #expect(sent.isEmpty)
        #expect(s.stop(groupID: g.id, pids: g.pids, force: false) == .done(count: 1) && sent == [[100]])
    }

    /// Docker okuması örnekleyiciye akar: gruplar projeye bölünür, Docker CPU serisi ve durum Snapshot'ta.
    @Test func dockerFlowsIntoSnapshot() async {
        let p = FakeProbe(busyCores: 1)
        p.extra.withLock { $0 = [ProcessRecord(pid: 900, ppid: 1, uid: 501, name: "com.apple.Virtualization.VirtualMachine", path: nil, args: [],
                                               cwd: nil, start: Date(timeIntervalSince1970: 1_793_000_000), hasTTY: false, cpuTime: 0,
                                               footprint: 10 << 30, energy: 0, diskWritten: 0)] }
        let api = FakeDockerAPI()
        api.state.withLock { $0.list = [FakeDockerAPI.raw("verifier"), FakeDockerAPI.raw("pg")]; $0.cpu = ["verifier": 62, "pg": 8] }
        let s = LiveSource(probe: p, historyURL: nil, persistToday: false, autostart: false, dockerAPI: api)
        s.setDetailInterest(true)
        await s.docker.poll(at: t0)
        await tick(s, p, 0)
        await s.docker.poll(at: t0.addingTimeInterval(2))
        await tick(s, p, 2)
        #expect(s.snapshot.capabilities.docker && s.snapshot.docker.running && s.snapshot.docker.containers.count == 2)
        #expect(s.snapshot.groups.first { $0.id == "docker:project:deploy" }?.context == "deploy · 2 container")
        await tick(s, p, 6)                                   // m10 adımı 5 sn: yeni kova yalnızca son okumayı taşır
        #expect(s.series(.dockerCPU, range: .m10).last.map { abs($0 - 70) < 1e-6 } == true)
        #expect(s.docker.interest.withLock { $0 })
    }

    /// Docker diskinin 30 günlük gidişatı geçmişten gelir (günlük ortalama).
    @Test func dockerTrendComesFromHistory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mystat-trend-\(UUID().uuidString).sqlite")
        let today = Fmt.calendar.startOfDay(for: Date())
        do {
            let h = try HistoryStore(url: url)
            for hour in 0..<3 { h.append([(.dockerDisk, 20)], at: today.addingTimeInterval(-86_400 + Double(hour) * 3600 + 60)) }
            h.append([(.dockerDisk, 23)], at: today.addingTimeInterval(60))
            h.flush()
            h.close()
        }
        let s = LiveSource(probe: FakeProbe(), historyURL: url, persistToday: false, autostart: false, dockerAPI: FakeDockerAPI())
        #expect(s.series(.dockerTrend30, range: .m10) == [20, 23])
    }
}
