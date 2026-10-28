import Foundation
import Observation

public enum SeriesKey: Hashable, Sendable {
    case cpu, cpuSystem, memUsed, memPressure, netDown, netUp, diskRead, diskWrite
    case temp, fan, power, gpu, battery, dockerCPU, dockerTrend30
    case group(String)
}

/// Arayüzün gördüğü tek veri kaynağı. Faz 1'de `SampleSource`, Faz 2'de gerçek kaynak.
@MainActor
public protocol MetricsSource: AnyObject, Observable {
    var snapshot: Snapshot { get }
    func series(_ key: SeriesKey, range: TimeRange) -> [Double]
    var diskTree: DiskTree { get }
    /// Disk haritasından silinen alanı doluluğa yansıtır (Faz 1'de örnek; Faz 2'de yeniden ölçüm).
    func applyDeletion(gb: Double)
    /// Panel ya da monitör açık mı: süreç listesi açıkken 2 sn, kapalıyken 5 sn (spec §9.2).
    func setDetailInterest(_ visible: Bool)
    /// Grubun süreçlerine SIGTERM (`force` ise SIGKILL); yalnızca kendi süreçlerin (spec §7.4).
    func stop(groupID: String, force: Bool) -> StopOutcome
}

public enum StopOutcome: Sendable, Equatable {
    case done(count: Int)
    case notPermitted(reason: String)
    case notFound

    /// Grupta kullanıcının olmayan süreç varken; arayüz düğmeleri pasif gösterir ve bunu yazar.
    public static let foreignReason = "Bu grubun bazı süreçleri sistemin; yalnızca kendi süreçlerin kapatılabilir."
}
