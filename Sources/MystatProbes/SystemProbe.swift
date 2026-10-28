import Foundation
import MystatCore

/// Canlı kaynağın sistemden okuduğu her şey. Yalnızca ham sayaç döndürür; anlam Core'da hesaplanır.
/// Testler sahte bir uygulamayla deterministik çalışır. Sonraki tasklar bu protokolü genişletir.
public protocol SystemProbe: Sendable {
    func coreTicks() -> [CoreTicks]
    func vm() -> VMCounters
    func loadAverage() -> [Double]
    func interfaces() -> [InterfaceCounters]
    func primaryInterface() -> String?
    func localIPv4(of iface: String) -> String?
    func dataVolume() -> VolumeCapacity
    func diskIO() -> DiskIOCounters
    func processes() -> [ProcessRecord]
    func listeningPorts(pids: [Int32]) -> [Int32: [Int]]
    func thermal() -> Level
    func battery() -> BatteryReading?
    func machine() -> MachineInfo
    /// İndirilenler'in üst seviyesindeki ≥ 2 GB ve ≥ 14 gündür açılmamış dosyalar (spec §7.3).
    func largeOldDownloads(now: Date) -> [(name: String, gb: Double, idleDays: Int)]
}
