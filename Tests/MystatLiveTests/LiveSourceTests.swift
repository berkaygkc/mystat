import Foundation
import MystatCore
import MystatProbes
import Synchronization
import MystatTestSupport
import Testing
@testable import MystatLive

/// A scripted fake system: on each call the counters advance by `step`.
final class FakeProbe: SystemProbe {
    let calls = Mutex<[String: Int]>([:])
    let step = Mutex(0)
    let busyCores: Double
    /// Start time of pid 100; if it changes, the pid has moved to a different process.
    let start100 = Mutex(Date(timeIntervalSince1970: 1_793_000_000))
    /// Additional own processes (other groups).
    let extra = Mutex<[ProcessRecord]>([])
    /// Scripted sensors (default: no sensors).
    struct Sensors {
        var map: SensorMap?
        var smc: [String: Double] = [:]
        var maxKeysPerCall = 0
        var energyCalls = 0, gpuClientCalls = 0
        var energyJ = 0.0, gpuNs: UInt64 = 0
    }
    let sensors = Mutex(Sensors())

    init(busyCores: Double = 0) { self.busyCores = busyCores }

    func count(_ k: String) { calls.withLock { $0[k, default: 0] += 1 } }
    func n(_ k: String) -> Int { calls.withLock { $0[k] ?? 0 } }
    func advance() { step.withLock { $0 += 1 } }
    var s: UInt64 { UInt64(step.withLock { $0 }) }

    // 2 cores; at each step core 0 is 80/100 busy (60 user + 20 system), core 1 is 50/100.
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
    func dataVolume() -> VolumeCapacity { count("dataVolume"); return VolumeCapacity(total: 500_000_000_000, available: 175_000_000_000, availableImportant: 187_000_000_000) }
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
    func sensorMap() -> SensorMap? { sensors.withLock { $0.map } }
    func smcValues(_ keys: [String]) -> [String: Double] {
        sensors.withLock { s in
            s.maxKeysPerCall = max(s.maxKeysPerCall, keys.count)
            return s.smc.filter { keys.contains($0.key) }
        }
    }
    func energy() -> EnergyCounters? {
        sensors.withLock { s in
            guard s.map != nil else { return nil }
            s.energyCalls += 1; s.energyJ += 100          // +100 J CPU and +10 J GPU on each call
            return EnergyCounters(cpuJ: s.energyJ, gpuJ: s.energyJ / 10, aneJ: 0, dramJ: 0)
        }
    }
    func gpu(clients: Bool) -> GPUReading? {
        sensors.withLock { s in
            guard s.map != nil else { return nil }
            if clients { s.gpuClientCalls += 1; s.gpuNs += 1_200_000_000 }
            return GPUReading(utilization: 28, cores: 20, clients: clients ? [GPUClient(pid: 100, name: "claude", gpuTimeNs: s.gpuNs)] : [])
        }
    }
}

@MainActor @Suite(.language("tr")) struct LiveSourceTests {
    let t0 = Date(timeIntervalSince1970: 1_793_163_600)

    /// When the language changes, measurement-side texts (facts, group context) refresh without waiting for the next 2 s.
    @Test func languageChangeResamples() async {
        let s = source(FakeProbe())
        await s.step(at: Date())
        #expect(s.snapshot.net.details.first?.label == "Arayüz")
        await L10n.$override.withValue("en") {
            s.languageChanged()
            await s.pendingResample?.value
        }
        #expect(s.snapshot.net.details.first?.label == "Interface")
    }

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
        #expect(p.n("processes") == 2)                  // at 0 and 6 s (5 s while closed)
        #expect(p.n("ports") == 0)                      // light mode: ports are not read
        s.setDetailInterest(true)
        for t in stride(from: 8.0, through: 14, by: 2) { await tick(s, p, t) }
        #expect(p.n("processes") == 6)                  // every round while open
    }

    @Test func groupsAndResidualSystemRow() async {
        let p = FakeProbe(busyCores: 1.2), s = source(p)
        s.setDetailInterest(true)
        await tick(s, p, 0)
        await tick(s, p, 2)
        let claude = s.snapshot.groups.first { $0.name == "Claude Code" }
        #expect(claude.map { abs($0.cpuCores - 1.2) < 0.01 } == true)
        #expect(claude?.pids == [100])
        // total 65% × 2 cores = 1.3 cores; Claude 1.2 → the remaining 0.1 goes on the "macOS" row
        let mac = s.snapshot.groups.first { $0.id == "sys:macos" }
        #expect(mac.map { abs($0.cpuCores - 0.1) < 0.01 } == true)
        #expect(s.series(.group(claude!.id), range: .m10).last.map { abs($0 - 1.2) < 0.01 } == true)
    }

    @Test func sustainedLoadBecomesIncident() async {
        let p = FakeProbe(busyCores: 1.3), s = source(p)   // no single group ≥ 2; total 65% < 70%
        for t in stride(from: 0.0, through: 130, by: 2) { await tick(s, p, t) }
        #expect(s.snapshot.incident == nil)
        let q = FakeProbe(busyCores: 4.5), h = source(q)   // a single group ≥ 4 cores, 2 min
        h.setDetailInterest(true)
        for t in stride(from: 0.0, through: 126, by: 2) { await tick(h, q, t) }
        #expect(h.snapshot.incident?.kind == .cpu && h.snapshot.incident?.level == .crit)
    }

    /// The signal goes to the group members that are still the same process in the current list.
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
        p.start100.withLock { $0 = $0.addingTimeInterval(5) }   // pid 100 is now a different process
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

    /// The `--log-values` line: tools/consistency.sh prints it side by side with top and vm_stat.
    @Test func logLineCarriesComparableValues() async {
        let p = FakeProbe(), s = source(p)
        await tick(s, p, 0)
        await tick(s, p, 2)
        let line = LiveSource.logLine(s.snapshot)
        #expect(line.hasPrefix("mystat cpu=65.0 user=55.0 sys=10.0 mem=54.0 "))
        #expect(line.contains(" memGB=") && line.contains(" down=2.40 up=0.30"))
        var d = SampleSource(seed: 1).snapshot
        d.docker.containers = Array(d.docker.containers.prefix(2))
        let dl = LiveSource.logLine(d)                                   // tools/docker-check.sh compares these with the docker CLI
        #expect(dl.contains(" containers=2 ") && dl.contains(" dockerCPU=") && dl.contains(" dockerMem="))
        #expect(dl.contains(" imgReclaim=2.80 volReclaim=12.60 volAnon=7.10"))
        #expect(dl.contains(" chip=48.0 gpuT=41.0 fan=0 pstr=14.0 cpuW=6.0 gpuW=1.0 gpu=6 "))   // tools/sensor-check.sh
        #expect(dl.hasSuffix(" rtr=192.168.1.1 lat=18.0 top=Docker"))   // tools/net-check.sh
        var n = d; n.net.latencyMs = .nan; n.net.details = []; n.groups = []
        #expect(LiveSource.logLine(n).hasSuffix(" rtr=- lat=- top=-"))
    }

    /// While the confirmation dialog is open, a group's identity can pass to another session (two sessions in the same folder, one finished):
    /// the signal goes only to those members from when the dialog opened that are still in the group.
    @Test func stopOnlyHitsMembersFromConfirmTime() async {
        let p = FakeProbe(busyCores: 1), s = source(p)
        var sent: [[Int32]] = []
        s.signaler = { pids, _ in sent.append(pids); return .done(count: pids.count) }
        s.setDetailInterest(true)
        await tick(s, p, 0)
        await tick(s, p, 2)
        let g = s.snapshot.groups.first { $0.name == "Claude Code" }!
        #expect(s.stop(groupID: g.id, pids: [999], force: false) == .notFound)
        // it was in the group when the dialog opened, and is alive now but in another group (e.g. the session that inherited the identity)
        p.extra.withLock { $0 = [ProcessRecord(pid: 300, ppid: 1, uid: 501, name: "node", path: "/opt/homebrew/bin/node", args: ["node", "x.js"],
                                               cwd: "/tmp", start: Date(timeIntervalSince1970: 1_793_000_000), hasTTY: false, cpuTime: 0,
                                               footprint: 1 << 20, energy: 0, diskWritten: 0)] }
        await tick(s, p, 4)
        #expect(s.stop(groupID: g.id, pids: [300], force: false) == .notFound)
        #expect(sent.isEmpty)
        #expect(s.stop(groupID: g.id, pids: g.pids, force: false) == .done(count: 1) && sent == [[100]])
    }

    /// Docker readings flow into the sampler: groups are split by project, and the Docker CPU series and state appear in the Snapshot.
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
        await tick(s, p, 6)                                   // the m10 step is 5 s: the new bucket carries only the last reading
        #expect(s.series(.dockerCPU, range: .m10).last.map { abs($0 - 70) < 1e-6 } == true)
        #expect(s.docker.interest.withLock { $0 })
    }

    /// Docker disk's 30-day trend comes from history (daily average).
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

    func withSensors(_ p: FakeProbe) {
        p.sensors.withLock {
            $0.map = SensorMap(cpu: ["Te04", "Tp1i"], gpu: ["Tg05"], battery: "TB0T", fans: 2)
            $0.smc = ["Tp1i": 54, "Te04": 60, "F0Ac": 1356, "F1Ac": 1471, "F0Mn": 1350, "PSTR": 29, "Tg05": 61, "TB0T": 29.4]
        }
    }

    @Test func sensorsFlowIntoSnapshot() async {
        let p = FakeProbe(), s = source(p)
        withSensors(p)
        await tick(s, p, 0)
        await tick(s, p, 2)
        let sys = s.snapshot.system
        #expect(s.snapshot.capabilities.sensors && sys.chipTemp == 57 && sys.fanRPM == 1471 && sys.fanCount == 2 && sys.fanMinRPM == 1350)
        #expect(sys.watts == 29 && sys.gpuPercent == 28 && sys.gpuCores == 20)
        #expect(s.series(.temp, range: .m10).last == 57 && s.series(.power, range: .m10).last == 29)
    }

    /// When idle (panel and monitor closed) a single read touches at most 10 SMC keys; IOReport and GPU clients are not read.
    @Test func idleReadsAtMostTenKeys() async {
        let p = FakeProbe(), s = source(p)
        withSensors(p)
        p.sensors.withLock {                                          // multi-key machine: the sample is limited to 7 keys
            $0.map?.cpu += (0..<20).map { String(format: "Tp%02d", $0) }
            for k in 0..<20 { $0.smc[String(format: "Tp%02d", k)] = 57 }
        }
        for t in stride(from: 0.0, through: 12, by: 2) { await tick(s, p, t) }
        let st = p.sensors.withLock { $0 }
        #expect(s.snapshot.system.chipTemp > 50)                     // read even when idle ("always")
        #expect(st.maxKeysPerCall <= 10 && st.energyCalls == 0 && st.gpuClientCalls == 0)
    }

    @Test func detailAddsGPUAndPower() async {
        let p = FakeProbe(busyCores: 1), s = source(p)
        withSensors(p)
        s.setDetailInterest(true)
        for t in stride(from: 0.0, through: 12, by: 2) { await tick(s, p, t) }
        let sys = s.snapshot.system
        #expect(sys.cpuWatts != nil && sys.gpuWatts != nil && sys.gpuTemp == 61)
        #expect(sys.gpuApps.first?.name == "Claude Code")             // under the name of pid 100's group
    }

    @Test func noSensorsKeepsCalmState() async {
        let p = FakeProbe(), s = source(p)
        await tick(s, p, 0)
        await tick(s, p, 2)
        #expect(!s.snapshot.capabilities.sensors && s.snapshot.system.chipTemp == 0)
    }

    /// When the panel/monitor closes, fields that are read only while open are cleared: hours later, stale GPU apps do not show when it reopens.
    @Test func detailOffClearsDetailFields() async {
        let p = FakeProbe(busyCores: 1), s = source(p)
        withSensors(p)
        s.setDetailInterest(true)
        for t in stride(from: 0.0, through: 12, by: 2) { await tick(s, p, t) }
        #expect(!s.snapshot.system.gpuApps.isEmpty)
        s.setDetailInterest(false)
        for t in stride(from: 14.0, through: 26, by: 2) { await tick(s, p, t) }
        let sys = s.snapshot.system
        #expect(sys.gpuApps.isEmpty && sys.cpuWatts == nil && sys.gpuWatts == nil && sys.gpuTemp == 0 && sys.chipTemp == 57)
    }

    /// Downloads is checked only if Full Disk Access is granted: otherwise macOS opened a permission dialog every time.
    @Test func downloadsOnlyWithFullDiskAccess() async {
        let t0 = Date()
        let p = FakeProbe()
        let without = Sampler(probe: p, history: nil, persistToday: false, fullDiskAccess: { false })
        without.interest.withLock { $0 = true }
        _ = await without.sample(at: t0); _ = await without.sample(at: t0.addingTimeInterval(601))
        #expect(p.n("downloads") == 0)
        let q = FakeProbe()
        let with = Sampler(probe: q, history: nil, persistToday: false, fullDiskAccess: { true })
        with.interest.withLock { $0 = true }
        _ = await with.sample(at: t0); _ = await with.sample(at: t0.addingTimeInterval(2))
        #expect(q.n("downloads") == 1)   // once every 10 min
        _ = await with.sample(at: t0.addingTimeInterval(601))
        #expect(q.n("downloads") == 2)
    }

    /// After a deletion, disk fullness is read at the next sample without waiting 60 s.
    @Test func volumeReReadOnRequest() async {
        let p = FakeProbe()
        let s = Sampler(probe: p, history: nil, persistToday: false)
        let t0 = Date()
        _ = await s.sample(at: t0); _ = await s.sample(at: t0.addingTimeInterval(2))
        #expect(p.n("dataVolume") == 1)
        await s.requestVolume()
        _ = await s.sample(at: t0.addingTimeInterval(4))
        #expect(p.n("dataVolume") == 2)
    }

    /// While the Disk section is open the tree stays in memory; with another section open or the monitor closed it is dropped.
    @Test func diskSectionVisibilityLoadsAndDropsTree() async throws {
        let fx = try DiskScanControllerTests.Fixture()
        let s = LiveSource(probe: FakeProbe(), historyURL: nil, persistToday: false, autostart: false, dockerAPI: FakeDockerAPI(),
                           disk: fx.controller())
        #expect(LiveSource.capabilities.diskScan)
        s.setVisibleSection("disk"); s.startDiskScan(); await s.disk.waitUntilIdle()
        #expect(s.diskTree.node(at: ["a"]) != nil)
        if case .ready = s.diskScan {} else { Issue.record("\(s.diskScan)") }
        s.setVisibleSection("net")
        #expect(s.diskTree.root.children == nil)
        s.setVisibleSection("disk"); await s.disk.waitUntilIdle()
        #expect(s.diskTree.node(at: ["a"]) != nil)
        s.setVisibleSection(nil)
        #expect(s.diskTree.root.children == nil)
    }

    /// Per-app network rates older than 5 s are not written to groups (counters are read every 2 s).
    @Test func staleNetRatesIgnored() async throws {
        let p = FakeProbe()
        let net = NetDetailPoller(link: { nil }, ping: { _ in nil }, sockets: { nil }, receiveFactor: { nil }, autoTick: false)
        let s = Sampler(probe: p, history: nil, persistToday: false, net: net)
        let t0 = Date()
        _ = await s.sample(at: t0)
        net.latest.withLock { $0.rates = [100: 3]; $0.ratesAt = t0.addingTimeInterval(-11) }
        let stale = await s.sample(at: t0.addingTimeInterval(2))
        #expect(stale.snapshot.groups.allSatisfy { $0.netMBps == 0 })
        net.latest.withLock { $0.ratesAt = t0.addingTimeInterval(3) }
        let fresh = await s.sample(at: t0.addingTimeInterval(4))
        let g = try #require(fresh.snapshot.groups.first { $0.pids.contains(100) })
        #expect(g.netMBps == 3)
        let older = await s.sample(at: t0.addingTimeInterval(11))   // the sample from 8 s ago: stale
        #expect(older.snapshot.groups.first { $0.pids.contains(100) }?.netMBps == 0)
    }

    @Test func liveSourceNetDetails() async {
        let f = NetFakes(), poller = f.poller()
        let s = LiveSource(probe: FakeProbe(), historyURL: nil, persistToday: false, autostart: false, dockerAPI: FakeDockerAPI(), net: poller)
        #expect(LiveSource.capabilities.netDetails)
        s.setVisibleSection("net"); await poller.sync()
        #expect(f.n(f.factorCalls) == 1); #expect(await poller.isVisible)
        s.setVisibleSection("docker"); await poller.sync()
        #expect(await poller.isVisible == false)
    }

    /// When the monitor is covered or minimized, network details stop (only while visible; a 2 s ping keeps Wi‑Fi awake).
    @Test func occludedMonitorStopsNetDetails() async {
        let f = NetFakes(), poller = f.poller()
        let s = LiveSource(probe: FakeProbe(), historyURL: nil, persistToday: false, autostart: false, dockerAPI: FakeDockerAPI(), net: poller)
        s.setVisibleSection("net"); await poller.sync()
        #expect(await poller.isVisible)
        s.setMonitorOccluded(true); await poller.sync()
        #expect(await poller.isVisible == false)
        s.setMonitorOccluded(false); await poller.sync()
        #expect(await poller.isVisible)
    }
}
