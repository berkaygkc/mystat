import Foundation

/// Memory state from page counters, using the same definitions as the system's built-in memory view.
/// Units are binary GB (1024³): a 48 GB machine shows as "48.00 GB".
public enum MemoryMeter {
    static let gib = 1_073_741_824.0

    public static func state(_ c: VMCounters) -> MemoryState {
        let page = Double(c.pageSize)
        let apps = Double(c.internal &- min(c.purgeable, c.internal)) * page / gib   // apps = internal − purgeable
        let wired = Double(c.wired) * page / gib
        let compressed = Double(c.compressor) * page / gib
        let total = Double(c.total) / gib
        let used = min(total, apps + wired + compressed)
        let level: Level = c.pressureLevel >= 4 ? .crit : c.pressureLevel >= 2 ? .warn : .ok
        return MemoryState(percent: total > 0 ? used / total * 100 : 0, usedGB: used, totalGB: total,
                           apps: apps, wired: wired, compressed: compressed, free: total - used,
                           pressurePercent: Double(100 - min(100, max(0, c.memoryLevel))), pressureLevel: level,
                           swapGB: Double(c.swapUsed) / gib)
    }
}
