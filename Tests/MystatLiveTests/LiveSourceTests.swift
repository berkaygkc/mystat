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
                              hasTTY: false, cpuTime: 0, footprint: 0, energy: 0, diskWritten: 0, restricted: true)]
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

    func source(_ p: FakeProbe) -> LiveSource { LiveSource(probe: p, historyURL: nil, persistToday: false, autostart: false) }

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
        #expect(s.snapshot.capabilities == LiveSource.capabilities2a)
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
        #expect(s.stop(groupID: id, force: true) == .done(count: 1))
        #expect(sent.count == 1 && sent[0].0 == [100] && sent[0].1)
        p.start100.withLock { $0 = $0.addingTimeInterval(5) }   // pid 100 artık başka süreç
        #expect(s.stop(groupID: id, force: false) == .notFound)
        #expect(sent.count == 1)
        #expect(s.stop(groupID: "yok", force: false) == .notFound)
    }

    @Test func stopRefusesSystemGroup() async {
        let p = FakeProbe(busyCores: 1), s = source(p)
        var called = false
        s.signaler = { _, _ in called = true; return .done(count: 1) }
        s.setDetailInterest(true)
        await tick(s, p, 0)
        await tick(s, p, 2)
        #expect(s.stop(groupID: "sys:macos", force: true) == .notPermitted(reason: StopOutcome.foreignReason))
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
    }
}
