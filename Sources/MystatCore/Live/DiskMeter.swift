import Foundation

/// Disk read/write rate (MB/s, decimal); interval and counter rules are the same as for the network.
public struct DiskIOMeter: Sendable {
    private var last: (c: DiskIOCounters, at: Date)?
    public init() {}

    public mutating func update(_ c: DiskIOCounters, at: Date) -> (read: Double, write: Double)? {
        defer { last = (c, at) }
        guard let prev = last else { return nil }
        let dt = at.timeIntervalSince(prev.at)
        guard dt > 0, dt <= SampleGap.maxInterval, c.bytesRead >= prev.c.bytesRead, c.bytesWritten >= prev.c.bytesWritten else { return nil }
        return (Double(c.bytesRead - prev.c.bytesRead) / 1e6 / dt, Double(c.bytesWritten - prev.c.bytesWritten) / 1e6 / dt)
    }
}

/// Fill level of the Data volume. Decimal GB (same as Finder).
public enum DiskMeter {
    public static func state(_ v: VolumeCapacity, io: (read: Double, write: Double)?) -> DiskState {
        let total = Double(v.total) / 1e9
        let important = Double(max(v.availableImportant, v.available)) / 1e9
        let free = Double(v.available) / 1e9
        let used = max(0, total - important)
        return DiskState(percent: total > 0 ? used / total * 100 : 0, freeGB: free, usedGB: used,
                         purgeableGB: max(0, important - free), readMBps: io?.read ?? 0, writeMBps: io?.write ?? 0)
    }
}
