import Foundation
import MystatCore
import MystatProbes
import Synchronization

/// Sampling loop. Every 2 s: CPU, memory, network, disk activity. Processes every round while the panel/monitor is open,
/// every 5 s when closed, without reading listening ports. Disk usage and battery every 60 s. The Downloads suggestion every
/// 10 min while the panel/monitor is open, and only with Full Disk Access.
public actor Sampler {
    public struct Output: Sendable {
        public let snapshot: Snapshot
        public let series: SeriesBuffer
        public let groups: GroupHistory
        /// Start times of our own processes in the last process list: when stopping, checks that the pid is still the same process.
        public let starts: [Int32: Date]
    }

    private struct ProcKey: Hashable { let pid: Int32; let start: Date }

    private let probe: any SystemProbe
    /// Downloads is a protected folder: reading it without Full Disk Access would open a macOS permission dialog, so the
    /// suggestion is only checked when access is already granted.
    private let fullDiskAccess: @Sendable () -> Bool
    private let history: HistoryStore?
    /// Docker is read at its own pace; only its latest reading is picked up here (the round does not wait even if Docker hangs).
    private let docker: DockerPoller?
    private var dockerReading = DockerPoller.Reading()
    private var lastDockerDisk: Date?
    /// 30-day delta of Docker's data; computed from history as df is refreshed.
    private var dockerTrend: Double?
    // Sensors: every 5 s; ≤ 10 SMC keys when idle, plus GPU temperature, IOReport and GPU apps while watched.
    private var sensorMap: SensorMap?
    private var sensors: SensorReading?
    private var lastSensors: Date?, lastSlowSensors: Date?
    private var slow: (ssd: Double?, battery: Double?, fanMin: Double) = (nil, nil, 0)
    private var powerMeter = PowerMeter(), gpuShare = GPUShare(), energyMeter = EnergyMeter()
    private var groupNameByPid: [Int32: String] = [:]
    /// So that today's network total is not lost on restart (off in tests).
    private let persistToday: Bool
    /// Whether the panel or monitor is open; written concurrently from the main actor.
    nonisolated let interest = Mutex(false)

    private var cpuMeter = CPUMeter(), netMeter: NetMeter, ioMeter = DiskIOMeter(), procMeter = ProcessMeter()
    private var engine = IncidentEngine()
    private let classes = ProcessGrouper.ClassCache()
    private var series = SeriesBuffer(), groupHistory = GroupHistory()
    private var lastCPU: CPUState?, lastNet = (down: 0.0, up: 0.0, todayDown: 0.0, todayUp: 0.0), lastIO: (read: Double, write: Double)?
    private var lastProc: Date?, lastSlow: Date?, lastDownloads: Date?, lastPrune: Date?
    private var groups: [ProcessGroup] = [], ports: [Int32: [Int]] = [:], written: [ProcKey: UInt64] = [:], starts: [Int32: Date] = [:]
    private var volume: VolumeCapacity?, battery: BatteryReading?, downloads: [(name: String, gb: Double, idleDays: Int)] = []
    private var iface: String?, ip: String?
    private let net: NetDetailPoller?
    /// Location permission state (shown on the Connection card when there is no network name); written by LiveSource.
    nonisolated let ssidAccess = Mutex(SSIDAccess.needsPermission)
    private var swap: [Double] = []
    private var recorded: String?
    private var netSaves = 0
    private let machine: MachineInfo
    private var loop: Task<Void, Never>?

    static let todayKey = "mystat.net.today"

    public init(probe: some SystemProbe, history: HistoryStore?, persistToday: Bool, docker: DockerPoller? = nil, net: NetDetailPoller? = nil,
                fullDiskAccess: @escaping @Sendable () -> Bool = { DiskAccess.hasFullDiskAccess() }) {
        self.probe = probe
        self.fullDiskAccess = fullDiskAccess
        self.net = net
        self.history = history
        self.docker = docker
        self.persistToday = persistToday
        machine = probe.machine()
        let saved = persistToday ? UserDefaults.standard.array(forKey: Self.todayKey) : nil
        let today = saved.flatMap { a -> NetMeter.Today? in
            guard a.count == 3, let d = a[0] as? String, let dn = a[1] as? Double, let up = a[2] as? Double else { return nil }
            return NetMeter.Today(day: d, downGB: dn, upGB: up)
        }
        netMeter = NetMeter(primary: nil, today: today ?? NetMeter.Today(day: "", downGB: 0, upGB: 0))
    }

    public func start(publish: @escaping @Sendable (Output) async -> Void) {
        loop?.cancel()
        loop = Task {
            while !Task.isCancelled {
                await publish(sample(at: Date()))
                let frac = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 2)
                try? await Task.sleep(for: .seconds(2 - frac + 0.01))
            }
        }
    }

    public func stop() { loop?.cancel() }

    /// After a deletion: disk usage (and other slow readings) are read in the next sample without waiting for the 60 s.
    public func requestVolume() { lastSlow = nil }

    /// On language change: process groups (context texts) are rebuilt in the next sample.
    public func requestProcesses() { lastProc = nil }

    public func sample(at now: Date) -> Output {
        let wantDetail = interest.withLock { $0 }
        dockerReading = docker?.latest.withLock { $0 } ?? DockerPoller.Reading()
        let ticks = probe.coreTicks()
        if var c = cpuMeter.update(ticks, at: now) { c.loadAvg = probe.loadAverage(); lastCPU = c }
        let cpu = lastCPU ?? Snapshot.empty(capabilities: .all).cpu
        let memory = MemoryMeter.state(probe.vm())
        swap.append(memory.swapGB)
        if swap.count > 30 { swap.removeFirst(swap.count - 30) }

        // Slow ones: primary interface, disk usage, battery (60 s).
        if lastSlow.map({ now.timeIntervalSince($0) >= 60 }) ?? true {
            let primary = probe.primaryInterface()
            if primary != iface { netMeter = NetMeter(primary: primary, today: netMeter.today); iface = primary }
            ip = probe.localIPv4(of: primary ?? "en0")
            volume = probe.dataVolume()
            battery = probe.battery()
            lastSlow = now
        }
        if let n = netMeter.update(probe.interfaces(), at: now, calendar: Fmt.calendar) { lastNet = n }
        netSaves += 1
        if persistToday, netSaves % 30 == 0 { let t = netMeter.today; UserDefaults.standard.set([t.day, t.downGB, t.upGB], forKey: Self.todayKey) }
        if let io = ioMeter.update(probe.diskIO(), at: now) { lastIO = io }

        if wantDetail || (lastProc.map { now.timeIntervalSince($0) >= 5 } ?? true) {
            sampleProcesses(at: now, detail: wantDetail, cpu: cpu, memory: memory, coreCount: ticks.count)
        }
        if lastSensors.map({ now.timeIntervalSince($0) >= 4.9 }) ?? true {
            readSensors(at: now, detail: wantDetail)
            lastSensors = now
        }
        if wantDetail, lastDownloads.map({ now.timeIntervalSince($0) >= 600 }) ?? true {
            downloads = fullDiskAccess() ? probe.largeOldDownloads(now: now) : []
            lastDownloads = now
        }

        // Series and history.
        let disk = DiskMeter.state(volume ?? VolumeCapacity(total: 0, available: 0, availableImportant: 0), io: lastIO)
        var samples: [(SeriesKey, Double)] = [(.memUsed, memory.percent), (.memPressure, memory.pressurePercent),
                                               (.netDown, lastNet.down), (.netUp, lastNet.up),
                                               (.diskRead, disk.readMBps), (.diskWrite, disk.writeMBps)]
        if lastCPU != nil { samples += [(.cpu, cpu.percent), (.cpuSystem, cpu.systemPercent)] }
        if let b = battery { samples.append((.battery, b.percent)) }
        if let r = sensors {
            samples += [(.temp, r.chipTemp), (.fan, r.fanRPM), (.gpu, r.gpuPercent)]
            if let w = r.systemWatts { samples.append((.power, w)) }
        }
        let containers = dockerReading.running ? dockerReading.containers : []
        if dockerReading.running {
            samples += [(.dockerCPU, containers.reduce(0) { $0 + $1.cpuPercent }), (.dockerMem, containers.reduce(0) { $0 + $1.memoryMB } / 1024)]
            if let at = dockerReading.diskAt, at != lastDockerDisk, let d = dockerReading.disk {   // as df is refreshed (10 min)
                samples.append((.dockerDisk, d.dataGB))
                lastDockerDisk = at
            }
        }
        for (k, v) in samples { series.add(k, v, at: now) }
        history?.append(samples, at: now)
        if samples.contains(where: { $0.0 == .dockerDisk }) {
            dockerTrend = HistoryStore.trend(history?.daily(.dockerDisk, days: 30, now: now, calendar: Fmt.calendar) ?? [])
        }
        if lastPrune.map({ now.timeIntervalSince($0) >= 3600 }) ?? true { history?.prune(now: now); lastPrune = now }

        // Battery drain: on battery, the last 30 min (the last 61 points of the 1 h series, 30 s apart).
        var drain: Double?
        if let b = battery, !b.onAC {
            let pts = series.series(.battery, .h1).suffix(61)
            if pts.count >= 60, let first = pts.first, let last = pts.last { drain = max(0, first - last) }
        }

        var incident: Incident?
        if lastCPU != nil {
            incident = engine.update(IncidentInputs(cpu: cpu, memory: memory, swapGrowing: (swap.last ?? 0) - (swap.first ?? 0) > 0.1,
                                                    disk: disk, groups: groups, thermal: probe.thermal(), batteryDrain30m: drain,
                                                    onAC: battery?.onAC ?? true, memoryGrowthGB: groupHistory.memoryGrowthGB(),
                                                    diskWrittenGB1h: groupHistory.diskWrittenGB1h(), containers: containers), at: now)
            if let i = incident, recorded != "\(i.kind)\(i.startedAt)" { history?.recordIncident(i, at: now); recorded = "\(i.kind)\(i.startedAt)" }
        }

        // Per-app network (while the Network section is open, every 2 s): rates older than 5 s are not written.
        let netReading = net?.latest.withLock { $0 }
        var shown = groups
        if let r = netReading, let at = r.ratesAt, now.timeIntervalSince(at) <= 5 { NetRates.apply(r.rates, to: &shown) }
        var m = LiveMeasurements(cpu: cpu, memory: memory, disk: disk, net: lastNet, iface: iface ?? "—", ip: ip, groups: shown,
                                 thermal: probe.thermal(), battery: battery, batteryDrain30m: drain, machine: machine,
                                 downloads: downloads, coreCount: max(1, ticks.count), docker: dockerState(), sensors: sensors)
        m.link = netReading?.link; m.latencyMs = netReading?.latencyMs; m.perAppAvailable = netReading?.perAppAvailable ?? true
        m.ssidAccess = ssidAccess.withLock { $0 }
        m.perAppReady = netReading.map { $0.ratesAt != nil } ?? true
        var caps = LiveSource.capabilities
        caps.sensors = sensors != nil
        return Output(snapshot: SnapshotBuilder.build(m, incident: incident, capabilities: caps),
                      series: series, groups: groupHistory, starts: starts)
    }

    /// Processes → groups. Other users' processes cannot be measured; what remains of the total goes to the "macOS" row.
    private func sampleProcesses(at now: Date, detail: Bool, cpu: CPUState, memory: MemoryState, coreCount: Int) {
        let records = probe.processes()
        let cores = procMeter.update(records, at: now, maxGap: detail ? SampleGap.maxInterval : GroupHistory.gap) ?? [:]
        if detail {
            let candidates = ProcessGrouper.devServerCandidates(records, cache: classes)
            ports = candidates.isEmpty ? [:] : probe.listeningPorts(pids: candidates)
        }
        let own = records.filter { !$0.restricted }
        starts = Dictionary(own.map { ($0.pid, $0.start) }, uniquingKeysWith: { a, _ in a })
        let ownCores = own.reduce(0) { $0 + (cores[$1.pid] ?? 0) }
        let ownMemGB = Double(own.reduce(UInt64(0)) { $0 &+ $1.footprint }) / 1_073_741_824
        let residual = (cores: max(0, cpu.percent / 100 * Double(coreCount) - ownCores), memoryGB: max(0, memory.usedGB - ownMemGB))
        let watts = energyMeter.update(records, at: now, maxGap: detail ? SampleGap.maxInterval : GroupHistory.gap) ?? [:]
        groups = ProcessGrouper.groups(records, cores: cores, ports: ports, system: residual, now: now, home: NSHomeDirectory(), cache: classes,
                                       watts: watts)
        groups = DockerGroups.split(groups, containers: dockerReading.running ? dockerReading.containers : [])
        groupNameByPid = Dictionary(groups.flatMap { g in g.pids.map { ($0, g.name) } }, uniquingKeysWith: { a, _ in a })

        // Disk writes: per-process delta → group total.
        var nowWritten: [ProcKey: UInt64] = [:], delta: [Int32: UInt64] = [:]
        for r in own {
            let k = ProcKey(pid: r.pid, start: r.start)
            nowWritten[k] = r.diskWritten
            if let before = written[k], r.diskWritten >= before { delta[r.pid] = r.diskWritten - before }
        }
        written = nowWritten
        var byGroup: [String: UInt64] = [:]
        for g in groups { byGroup[g.id] = g.pids.reduce(0) { $0 &+ (delta[$1] ?? 0) } }
        groupHistory.add(groups, writtenBytes: byGroup, at: now)
        let avg = groupHistory.wattsAverage()   // instantaneous watts are too jittery: lists and incident culprits use the 10 min average
        for i in groups.indices { groups[i].watts = avg[groups[i].id] ?? groups[i].watts }
        lastProc = now
    }

    private func dockerState() -> DockerState {
        let r = dockerReading
        guard r.running else { return .notRunning }
        return DockerState(running: true, containers: r.containers, vmMemoryGB: r.vmMemoryGB, vmCores: r.vmCores,
                           disk: r.disk ?? DockerState.notRunning.disk, trend30GB: dockerTrend)
    }

    /// The chip average always comes from the same at most 7 keys (consistent when idle and when open); with 2 fans and system power, ≤ 10 keys.
    private func readSensors(at now: Date, detail: Bool) {
        if sensorMap == nil { sensorMap = probe.sensorMap() }   // nil while discovery is running; not waited for
        guard let map = sensorMap, !map.cpu.isEmpty else { sensors = nil; return }
        let cpuKeys = map.sample(map.cpu, max: 7), fanKeys = (0..<min(map.fans, 2)).map { "F\($0)Ac" }
        let v = probe.smcValues(cpuKeys + fanKeys + ["PSTR"])
        guard let chip = SensorMeter.average(cpuKeys.compactMap { v[$0] }) else { sensors = nil; return }
        if lastSlowSensors.map({ now.timeIntervalSince($0) >= 60 }) ?? true {
            let minKeys = (0..<min(map.fans, 2)).map { "F\($0)Mn" }
            let sv = probe.smcValues(minKeys + (map.battery.map { [$0] } ?? []))
            slow = (probe.ssdTemperature(), map.battery.flatMap { sv[$0] }, minKeys.compactMap { sv[$0] }.max() ?? 0)
            lastSlowSensors = now
        }
        // Readings taken only while the panel/monitor is open are not carried over while closed: so a stale value does not show when it is opened hours later.
        var r = SensorReading(chipTemp: chip, gpuTemp: detail ? sensors?.gpuTemp : nil, ssdTemp: slow.ssd, batteryTemp: slow.battery,
                              fanRPM: fanKeys.compactMap { v[$0] }.max() ?? 0, fanCount: map.fans, fanMinRPM: slow.fanMin,
                              systemWatts: v["PSTR"], cpuWatts: detail ? sensors?.cpuWatts : nil, gpuWatts: detail ? sensors?.gpuWatts : nil,
                              gpuPercent: 0, gpuCores: 0, gpuApps: detail ? sensors?.gpuApps ?? [] : [])
        if let g = probe.gpu(clients: detail) {
            r.gpuPercent = g.utilization
            r.gpuCores = g.cores
            if detail {   // the client name is truncated in the kernel ("Brave Browser He"): use the name of the pid's group instead
                let named = GPUReading(utilization: g.utilization, cores: g.cores, clients: g.clients.map {
                    GPUClient(pid: $0.pid, name: groupNameByPid[$0.pid] ?? $0.name, gpuTimeNs: $0.gpuTimeNs)
                })
                if let apps = gpuShare.update(named, at: now) { r.gpuApps = Array(apps.prefix(2)) }
            }
        }
        if detail {
            let gk = map.sample(map.gpu, max: 8)
            let gv = probe.smcValues(gk)
            r.gpuTemp = SensorMeter.average(gk.compactMap { gv[$0] })
            if let e = probe.energy(), let w = powerMeter.update(e, at: now) { r.cpuWatts = w.cpu; r.gpuWatts = w.gpu }
        }
        sensors = r
    }
}
