import Foundation
import MystatCore
import Observation

/// Gerçek veri kaynağı. Faz 2a'da Docker, sensörler, disk taraması ve ağ ayrıntısı henüz bağlı değil;
/// bunlar sahte sayı yerine sakin "bağlı değil" durumu gösterir.
@MainActor
@Observable
public final class LiveSource: MetricsSource {
    public static let capabilities2a = SourceCapabilities(docker: false, sensors: false, diskScan: false, netDetails: false)

    public private(set) var snapshot: Snapshot
    @ObservationIgnored public let diskTree = DiskTree(root: DiskNode("~", 0, []))

    public init() {
        snapshot = .empty(capabilities: Self.capabilities2a)
    }

    public func series(_ key: SeriesKey, range: TimeRange) -> [Double] { [] }
    public func applyDeletion(gb: Double) {}
    public func setDetailInterest(_ visible: Bool) {}
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
