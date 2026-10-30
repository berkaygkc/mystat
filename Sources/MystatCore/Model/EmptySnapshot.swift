import Foundation

public extension Snapshot {
    /// Calm state before the first measurement: zeros, no groups, no incidents.
    static func empty(capabilities: SourceCapabilities) -> Snapshot {
        Snapshot(
            cpu: CPUState(percent: 0, systemPercent: 0, cores: [], loadAvg: [0, 0, 0]),
            memory: MemoryState(percent: 0, usedGB: 0, totalGB: 0, apps: 0, wired: 0, compressed: 0, free: 0,
                                pressurePercent: 0, pressureLevel: .ok, swapGB: 0),
            disk: DiskState(percent: 0, freeGB: 0, usedGB: 0, purgeableGB: 0, readMBps: 0, writeMBps: 0),
            net: NetState(downMBps: 0, upMBps: 0, todayDownGB: 0, todayUpGB: 0, latencyMs: 0, iface: "", ssid: "", details: []),
            docker: .notRunning,
            system: SystemState(chipTemp: 0, gpuTemp: 0, ssdTemp: 0, fanRPM: 0, thermal: .ok, battery: 0, charging: false,
                                batteryDrain30m: nil, watts: 0, adapter: "", health: "", capacity: "", cycles: 0, gpuPercent: 0, gpuCores: 0),
            groups: [], incident: nil, suggestions: [], calmTop: ("", 0), capabilities: capabilities)
    }
}

public extension DockerState {
    /// Docker is unreachable (Docker Desktop is off or missing) or has not been read yet.
    static let notRunning = DockerState(running: false, containers: [], vmMemoryGB: 0, vmCores: 0,
                                        disk: DockerDisk(imagesGB: 0, imagesReclaimGB: 0, imagesCount: 0, volumesGB: 0, volumesReclaimGB: 0,
                                                         volumesCount: 0, buildCacheGB: 0, rawGB: nil))
}
