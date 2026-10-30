import Foundation

/// Sensor values: implausible readings (−9.201, 0, 3.4, above 150, NaN) are excluded from the average.
public enum SensorMeter {
    static let plausible = 10.0...120.0
    /// Sensors are read about every 5–6 s; the gap threshold is 3 ticks (the `SampleGap.maxInterval` for 2 s measurements would be exceeded on every round).
    public static let gap: TimeInterval = 15

    public static func average(_ values: [Double]) -> Double? {
        let ok = values.filter { $0.isFinite && plausible.contains($0) }
        return ok.isEmpty ? nil : ok.reduce(0, +) / Double(ok.count)
    }
}

/// IOReport cumulative joules → watts. nil on the first reading, after a long interval (sleep), when the counter goes backwards, or on an implausible
/// value: spikes are not shown.
public struct PowerMeter: Sendable {
    private var last: (e: EnergyCounters, at: Date)?
    public init() {}

    public mutating func update(_ e: EnergyCounters, at: Date) -> (cpu: Double, gpu: Double)? {
        defer { last = (e, at) }
        guard let p = last else { return nil }
        let dt = at.timeIntervalSince(p.at)
        guard dt > 0, dt <= SensorMeter.gap, e.cpuJ >= p.e.cpuJ, e.gpuJ >= p.e.gpuJ else { return nil }
        let cpu = (e.cpuJ - p.e.cpuJ) / dt, gpu = (e.gpuJ - p.e.gpuJ) / dt
        guard cpu <= 500, gpu <= 500 else { return nil }
        return (cpu, gpu)
    }
}

/// Client GPU time delta → percent per app (100% = the whole GPU used by one app). Key (pid, name): if the same pid
/// switches to another app, the old one's counter is not inherited. The name may be truncated in the kernel; completing it is the sampler's job.
public struct GPUShare: Sendable {
    private struct Key: Hashable { let pid: Int32; let name: String }
    private var last: (ns: [Key: UInt64], at: Date)?
    public init() {}

    public mutating func update(_ r: GPUReading, at: Date) -> [(name: String, percent: Double)]? {
        var now: [Key: UInt64] = [:]
        for c in r.clients { now[Key(pid: c.pid, name: c.name), default: 0] &+= c.gpuTimeNs }
        defer { last = (now, at) }
        guard let p = last else { return nil }
        let dt = at.timeIntervalSince(p.at)
        guard dt > 0, dt <= SensorMeter.gap else { return nil }
        var byName: [String: Double] = [:]
        for (k, ns) in now {
            guard let before = p.ns[k], ns > before else { continue }
            byName[k.name, default: 0] += Double(ns - before) / (dt * 1e9) * 100
        }
        return byName.map { ($0.key, $0.value) }.sorted { $0.percent > $1.percent }
    }
}
