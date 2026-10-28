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
}
