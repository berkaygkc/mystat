import Foundation
import MystatCore

/// Everything the live source reads from the system. Returns only raw counters; meaning is computed in Core.
/// Tests run deterministically with a fake implementation.
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
    /// Files at the top level of Downloads that are ≥ 2 GB and unopened for ≥ 14 days.
    func largeOldDownloads(now: Date) -> [(name: String, gb: Double, idleDays: Int)]
    /// Discovered SMC keys; nil while discovery is running or if there are no sensors (the sampling loop does not wait).
    func sensorMap() -> SensorMap?
    func smcValues(_ keys: [String]) -> [String: Double]
    func ssdTemperature() -> Double?
    func energy() -> EnergyCounters?
    /// `clients`: also per-app GPU time (a scan takes ≈ 1.6 ms; only while the panel/monitor is open).
    func gpu(clients: Bool) -> GPUReading?
}

/// A source without sensors (the tests' fake probe, other Macs): the calm "no sensors" state continues.
public extension SystemProbe {
    func sensorMap() -> SensorMap? { nil }
    func smcValues(_ keys: [String]) -> [String: Double] { [:] }
    func ssdTemperature() -> Double? { nil }
    func energy() -> EnergyCounters? { nil }
    func gpu(clients: Bool) -> GPUReading? { nil }
}
