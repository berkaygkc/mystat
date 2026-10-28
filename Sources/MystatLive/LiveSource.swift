import Foundation
import MystatCore
import MystatProbes
import Observation

/// Gerçek veri kaynağı. Ölçüm `Sampler` actor'ında; burada yalnızca son Snapshot ve seriler tutulur.
/// Faz 2a'da Docker, sensörler, disk taraması ve ağ ayrıntısı henüz bağlı değil; bunlar sahte sayı yerine
/// sakin "bağlı değil" durumu gösterir.
@MainActor
@Observable
public final class LiveSource: MetricsSource {
    public nonisolated static let capabilities2a = SourceCapabilities(docker: false, sensors: false, diskScan: false, netDetails: false)

    public private(set) var snapshot: Snapshot
    @ObservationIgnored public let diskTree = DiskTree(root: DiskNode("~", 0, []))
    @ObservationIgnored private var buffer = SeriesBuffer()
    @ObservationIgnored private var groupHistory = GroupHistory()
    @ObservationIgnored private let sampler: Sampler
    @ObservationIgnored private let history: HistoryStore?

    public init(probe: some SystemProbe = DefaultProbe(), historyURL: URL? = HistoryStore.defaultURL,
                persistToday: Bool = true, autostart: Bool = true) {
        snapshot = .empty(capabilities: Self.capabilities2a)
        let store = historyURL.flatMap { try? HistoryStore(url: $0) }
        history = store
        sampler = Sampler(probe: probe, history: store, persistToday: persistToday)
        if autostart { start() }
    }

    public func start() {
        let sampler = sampler
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
    }

    public func series(_ key: SeriesKey, range: TimeRange) -> [Double] {
        if case .group(let id) = key { return groupHistory.cores(id) }
        switch range {
        case .m10, .h1: return buffer.series(key, range)
        case .h24, .d7: return history?.series(key, range, now: Date()) ?? []
        }
    }

    public func applyDeletion(gb: Double) {}

    public func setDetailInterest(_ visible: Bool) { sampler.interest.withLock { $0 = visible } }

    public func stop(groupID: String, force: Bool) -> StopOutcome { .notFound }
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
