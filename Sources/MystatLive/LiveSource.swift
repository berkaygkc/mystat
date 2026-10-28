import Foundation
import MystatCore
import MystatProbes
import Observation

/// Gerçek veri kaynağı. Ölçüm `Sampler` actor'ında, Docker `DockerPoller`'da; burada yalnızca son Snapshot ve seriler tutulur.
/// Sensörler, disk taraması ve ağ ayrıntısı henüz bağlı değil; bunlar sahte sayı yerine sakin "bağlı değil" durumu gösterir.
@MainActor
@Observable
public final class LiveSource: MetricsSource {
    public nonisolated static let capabilities = SourceCapabilities(docker: true, sensors: false, diskScan: false, netDetails: false)

    public private(set) var snapshot: Snapshot
    @ObservationIgnored public let diskTree = DiskTree(root: DiskNode("~", 0, []))
    @ObservationIgnored private var buffer = SeriesBuffer()
    @ObservationIgnored private var groupHistory = GroupHistory()
    @ObservationIgnored private let sampler: Sampler
    @ObservationIgnored let docker: DockerPoller
    @ObservationIgnored private let history: HistoryStore?
    @ObservationIgnored private let probe: any SystemProbe
    @ObservationIgnored private var starts: [Int32: Date] = [:]
    /// Testler gerçek sinyal yerine kaydedici koyar.
    @ObservationIgnored var signaler: @MainActor ([Int32], Bool) -> StopOutcome = { ProcessActions.signal($0, force: $1) }

    public init(probe: some SystemProbe = DefaultProbe(), historyURL: URL? = HistoryStore.defaultURL,
                persistToday: Bool = true, autostart: Bool = true, dockerAPI: some DockerAPI = DockerClient()) {
        snapshot = .empty(capabilities: Self.capabilities)
        let store = historyURL.flatMap { try? HistoryStore(url: $0) }
        history = store
        self.probe = probe
        let docker = DockerPoller(api: dockerAPI)
        self.docker = docker
        sampler = Sampler(probe: probe, history: store, persistToday: persistToday, docker: docker)
        if autostart { start() }
    }

    public func start() {
        let sampler = sampler, docker = docker
        Task { await docker.start() }
        Task { [weak self] in
            await sampler.start { out in await MainActor.run { self?.apply(out) } }
        }
    }

    /// Testler örneklemeyi saatle sürer.
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

    public func applyDeletion(gb: Double) {}

    /// Uygulama kapanırken: geçmişin yarım kovaları yazılır.
    public func flushHistory() { history?.flush() }

    public func setDetailInterest(_ visible: Bool) {
        sampler.interest.withLock { $0 = visible }
        docker.interest.withLock { $0 = visible }
    }

    public func perform(_ action: DockerAction) async -> DockerActionOutcome { await docker.perform(action) }

    public func setVisibleSection(_ section: String?) {
        guard section == "docker" else { return }
        let docker = docker
        Task { await docker.requestDisk(at: Date()) }
    }

    /// `--log-values` (DEBUG) satırı; tools/consistency.sh top, vm_stat ve netstat ile, tools/docker-check.sh docker CLI ile karşılaştırır.
    public nonisolated static func logLine(_ s: Snapshot) -> String {
        func f(_ v: Double, _ d: Int) -> String { String(format: "%.\(d)f", v) }
        return "mystat cpu=\(f(s.cpu.percent, 1)) user=\(f(s.cpu.percent - s.cpu.systemPercent, 1)) sys=\(f(s.cpu.systemPercent, 1))"
            + " mem=\(f(s.memory.percent, 1)) memGB=\(f(s.memory.usedGB, 2)) down=\(f(s.net.downMBps, 2)) up=\(f(s.net.upMBps, 2))"
            + " containers=\(s.docker.containers.count) dockerCPU=\(f(s.docker.containers.reduce(0) { $0 + $1.cpuPercent }, 1))"
            + " dockerMem=\(f(s.docker.containers.reduce(0) { $0 + $1.memoryMB } / 1024, 2))"
            + " imgReclaim=\(f(s.docker.disk.imagesReclaimGB, 2)) volReclaim=\(f(s.docker.disk.volumesReclaimGB, 2)) volAnon=\(f(s.docker.disk.volumesAnonReclaimGB, 2))"
            + " chip=\(f(s.system.chipTemp, 1)) gpuT=\(f(s.system.gpuTemp, 1)) fan=\(f(s.system.fanRPM, 0)) pstr=\(f(s.system.watts, 1))"
            + " cpuW=\(f(s.system.cpuWatts ?? 0, 1)) gpuW=\(f(s.system.gpuWatts ?? 0, 1)) gpu=\(f(s.system.gpuPercent, 0))"
    }

    /// Grubun pid'leri o anki listeden yeniden çözülür: o arada biten ya da başka sürece geçmiş pid'e sinyal gitmez.
    /// Onay penceresi açıkken kimlik başka gruba geçmiş olabilir: yalnızca pencere açıldığındaki üyelerden hâlâ grupta olanlar.
    public func stop(groupID: String, pids confirmed: [Int32], force: Bool) -> StopOutcome {
        guard let g = snapshot.groups.first(where: { $0.id == groupID }) else { return .notFound }
        if g.foreign { return .notPermitted(reason: StopOutcome.foreignReason) }
        let members = Set(g.pids)
        let current = Dictionary(probe.processes().map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let pids = confirmed.filter { pid in members.contains(pid) && current[pid].map { !$0.restricted && $0.start == starts[pid] } == true }
        return pids.isEmpty ? .notFound : signaler(pids, force)
    }
}

/// Açılış argümanına göre kaynak: varsayılan canlı, `--sample` örnek veri (`--incident`, `--kind k` ile).
@MainActor
public enum SourceFactory {
    public static func make(arguments: [String]) -> any MetricsSource {
        guard arguments.contains("--sample") else { return LiveSource() }
        let kind = arguments.firstIndex(of: "--kind").flatMap { arguments.indices.contains($0 + 1) ? IncidentKind(rawValue: arguments[$0 + 1]) : nil } ?? .cpu
        return SampleSource(seed: 1, incident: arguments.contains("--incident"), kind: kind)
    }
}
