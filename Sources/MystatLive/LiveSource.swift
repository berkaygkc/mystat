import Foundation
import MystatCore
import MystatProbes
import Observation

/// Real data source. Sampling runs in the `Sampler` actor and Docker polling in `DockerPoller`; this only holds the latest Snapshot and series.
/// When a source is unavailable (no SMC sensors, Docker not running), the UI shows a calm "not connected" state instead of fake numbers.
@MainActor
@Observable
public final class LiveSource: MetricsSource {
    public nonisolated static let capabilities = SourceCapabilities(docker: true, sensors: false, diskScan: true, netDetails: true)

    public private(set) var snapshot: Snapshot
    @ObservationIgnored let disk: DiskScanController
    public var diskTree: DiskTree { disk.tree }
    public var diskScan: ScanPhase { disk.phase }
    public var diskInaccessible: Int { disk.inaccessible }
    /// Re-checked every time the Disk section opens (permission may have been granted in System Settings).
    public private(set) var diskFullAccess = DiskAccess.hasFullDiskAccess()
    @ObservationIgnored private var buffer = SeriesBuffer()
    @ObservationIgnored private var groupHistory = GroupHistory()
    @ObservationIgnored private let sampler: Sampler
    @ObservationIgnored let docker: DockerPoller
    @ObservationIgnored let net: NetDetailPoller
    @ObservationIgnored let location: LocationAccess
    @ObservationIgnored private var visibleSection: String?
    @ObservationIgnored private var occluded = false
    @ObservationIgnored private let history: HistoryStore?
    @ObservationIgnored private let probe: any SystemProbe
    @ObservationIgnored private var starts: [Int32: Date] = [:]
    /// Tests inject a recorder instead of the real signal.
    @ObservationIgnored var signaler: @MainActor ([Int32], Bool) -> StopOutcome = { ProcessActions.signal($0, force: $1) }

    public init(probe: some SystemProbe = DefaultProbe(), historyURL: URL? = HistoryStore.defaultURL,
                persistToday: Bool = true, autostart: Bool = true, dockerAPI: some DockerAPI = DockerClient(),
                disk: DiskScanController? = nil, net: NetDetailPoller? = nil, location: LocationAccess? = nil) {
        self.disk = disk ?? DiskScanController()
        let net = net ?? NetDetailPoller()
        self.net = net
        snapshot = .empty(capabilities: Self.capabilities)
        let store = historyURL.flatMap { try? HistoryStore(url: $0) }
        history = store
        self.probe = probe
        let docker = DockerPoller(api: dockerAPI)
        self.docker = docker
        sampler = Sampler(probe: probe, history: store, persistToday: persistToday, docker: docker, net: net)
        let location = location ?? LocationAccess()
        self.location = location
        let sampler0 = sampler
        sampler0.ssidAccess.withLock { $0 = location.status }
        location.onChange = { [weak location] in
            guard let location else { return }
            sampler0.ssidAccess.withLock { $0 = location.status }
            net.refreshLink()
        }
        if autostart { start() }
    }

    public func start() {
        let sampler = sampler, docker = docker
        Task { await docker.start() }
        Task { [weak self] in
            await sampler.start { out in await MainActor.run { self?.apply(out) } }
        }
    }

    /// On language change, sample immediately: facts, suggestions and group context are rebuilt in the new language (series use bucket averages, so an extra sample does no harm).
    @ObservationIgnored private(set) var pendingResample: Task<Void, Never>?

    public func languageChanged() {
        let sampler = sampler
        pendingResample = Task { [weak self] in
            await sampler.requestProcesses()
            let out = await sampler.sample(at: Date())
            self?.apply(out)
        }
    }

    /// Tests drive sampling with a clock.
    func step(at date: Date) async { apply(await sampler.sample(at: date)) }

    private func apply(_ o: Sampler.Output) {
        snapshot = o.snapshot
        buffer = o.series
        groupHistory = o.groups
        starts = o.starts
    }

    public func series(_ key: SeriesKey, range: TimeRange) -> [Double] {
        if case .group(let id) = key { return groupHistory.cores(id) }
        if key == .dockerTrend30 { return history?.daily(.dockerDisk, days: 30, now: Date(), calendar: Fmt.calendar) ?? [] }
        switch range {
        case .m10, .h1: return buffer.series(key, range)
        case .h24, .d7: return history?.series(key, range, now: Date()) ?? []
        }
    }

    public func delete(_ items: [BasketItem], mode: DeleteMode) async -> DeleteOutcome {
        let out = await disk.delete(items, mode: mode)
        await sampler.requestVolume()
        return out
    }

    /// On app quit: the history's partial buckets are written.
    public func flushHistory() { history?.flush() }

    public func setDetailInterest(_ visible: Bool) {
        sampler.interest.withLock { $0 = visible }
        docker.interest.withLock { $0 = visible }
    }

    public func perform(_ action: DockerAction) async -> DockerActionOutcome { await docker.perform(action) }

    public func setMonitorOccluded(_ occluded: Bool) {
        self.occluded = occluded
        net.setVisible(visibleSection == "net" && !occluded)
    }

    public func startDiskScan() { disk.start() }
    public func requestNetworkNameAccess() { location.request() }
    public func cancelDiskScan() { disk.cancel() }

    public func setVisibleSection(_ section: String?) {
        disk.setVisible(section == "disk")
        visibleSection = section
        net.setVisible(section == "net" && !occluded)
        if section == "disk", DiskAccess.hasFullDiskAccess() != diskFullAccess { diskFullAccess.toggle() }
        guard section == "docker" else { return }
        let docker = docker
        Task { await docker.requestDisk(at: Date()) }
    }

    /// The `--log-values` (DEBUG) line; tools/consistency.sh compares it with top, vm_stat and netstat, and tools/docker-check.sh with the docker CLI.
    public nonisolated static func logLine(_ s: Snapshot) -> String {
        func f(_ v: Double, _ d: Int) -> String { String(format: "%.\(d)f", v) }
        return "mystat cpu=\(f(s.cpu.percent, 1)) user=\(f(s.cpu.percent - s.cpu.systemPercent, 1)) sys=\(f(s.cpu.systemPercent, 1))"
            + " mem=\(f(s.memory.percent, 1)) memGB=\(f(s.memory.usedGB, 2)) down=\(f(s.net.downMBps, 2)) up=\(f(s.net.upMBps, 2))"
            + " containers=\(s.docker.containers.count) dockerCPU=\(f(s.docker.containers.reduce(0) { $0 + $1.cpuPercent }, 1))"
            + " dockerMem=\(f(s.docker.containers.reduce(0) { $0 + $1.memoryMB } / 1024, 2))"
            + " imgReclaim=\(f(s.docker.disk.imagesReclaimGB, 2)) volReclaim=\(f(s.docker.disk.volumesReclaimGB, 2)) volAnon=\(f(s.docker.disk.volumesAnonReclaimGB, 2))"
            + " chip=\(f(s.system.chipTemp, 1)) gpuT=\(f(s.system.gpuTemp, 1)) fan=\(f(s.system.fanRPM, 0)) pstr=\(f(s.system.watts, 1))"
            + " cpuW=\(f(s.system.cpuWatts ?? 0, 1)) gpuW=\(f(s.system.gpuWatts ?? 0, 1)) gpu=\(f(s.system.gpuPercent, 0))"
            + " rtr=\(router(s)) lat=\(s.net.latencyMs.isFinite ? f(s.net.latencyMs, 1) : "-") top=\(topDownloader(s))"
    }

    /// For tools/net-check.sh: router and top downloader (no spaces); "-" if unknown.
    private nonisolated static func router(_ s: Snapshot) -> String {
        s.net.details.first { $0.label == L10n.t("net.fact.router") }.map(\.value).flatMap { $0 == "—" ? nil : $0 } ?? "-"
    }
    private nonisolated static func topDownloader(_ s: Snapshot) -> String {
        GroupPresentation.networkUsers(s.groups).first.flatMap { $0.netMBps > 0 ? $0.name.replacingOccurrences(of: " ", with: "_") : nil } ?? "-"
    }

    /// The group's pids are re-resolved from the current list, so no signal goes to a pid that has exited or been reused by another process.
    /// While the confirmation dialog is open the identity may have moved to another group: only members from when the dialog opened that are still in the group are used.
    public func stop(groupID: String, pids confirmed: [Int32], force: Bool) -> StopOutcome {
        guard let g = snapshot.groups.first(where: { $0.id == groupID }) else { return .notFound }
        if g.foreign { return .notPermitted(reason: StopOutcome.foreignReason) }
        let members = Set(g.pids)
        let current = Dictionary(probe.processes().map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let pids = confirmed.filter { pid in members.contains(pid) && current[pid].map { !$0.restricted && $0.start == starts[pid] } == true }
        return pids.isEmpty ? .notFound : signaler(pids, force)
    }
}

/// Source chosen by launch argument: live by default, `--sample` for sample data (with `--incident`, `--kind k`).
@MainActor
public enum SourceFactory {
    public static func make(arguments: [String]) -> any MetricsSource {
        guard arguments.contains("--sample") else { return LiveSource() }
        let kind = arguments.firstIndex(of: "--kind").flatMap { arguments.indices.contains($0 + 1) ? IncidentKind(rawValue: arguments[$0 + 1]) : nil } ?? .cpu
        return SampleSource(seed: 1, incident: arguments.contains("--incident"), kind: kind)
    }
}
