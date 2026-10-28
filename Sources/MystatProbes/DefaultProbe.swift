import Foundation
import MystatCore

/// Gerçek sistemi okuyan probe: alt okuyuculara devreder.
public struct DefaultProbe: SystemProbe {
    let mach = MachProbe()
    let netDisk = NetDiskProbe()
    let procs = ProcessProbe()

    public init() {}

    public func coreTicks() -> [CoreTicks] { mach.coreTicks() }
    public func vm() -> VMCounters { mach.vm() }
    public func loadAverage() -> [Double] { mach.loadAverage() }
    public func interfaces() -> [InterfaceCounters] { netDisk.interfaces() }
    public func primaryInterface() -> String? { netDisk.primaryInterface() }
    public func localIPv4(of iface: String) -> String? { netDisk.localIPv4(of: iface) }
    public func dataVolume() -> VolumeCapacity { netDisk.dataVolume() }
    public func diskIO() -> DiskIOCounters { netDisk.diskIO() }
    public func processes() -> [ProcessRecord] { procs.processes() }
    public func listeningPorts(pids: [Int32]) -> [Int32: [Int]] { procs.listeningPorts(pids: pids) }
}
