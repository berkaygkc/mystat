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
    /// Keşfedilmiş SMC anahtarları; keşif sürerken ya da sensör yoksa nil (ölçüm döngüsü beklemez).
    func sensorMap() -> SensorMap?
    func smcValues(_ keys: [String]) -> [String: Double]
    func ssdTemperature() -> Double?
    func energy() -> EnergyCounters?
    /// `clients`: uygulama başına GPU süresi de (tarama ≈ 1,6 ms; yalnızca panel/monitör açıkken).
    func gpu(clients: Bool) -> GPUReading?
}

/// Sensörü olmayan kaynak (testlerin sahte probe'u, başka Mac'ler): Faz 2a'nın sakin durumu sürer.
public extension SystemProbe {
    func sensorMap() -> SensorMap? { nil }
    func smcValues(_ keys: [String]) -> [String: Double] { [:] }
    func ssdTemperature() -> Double? { nil }
    func energy() -> EnergyCounters? { nil }
    func gpu(clients: Bool) -> GPUReading? { nil }
}
