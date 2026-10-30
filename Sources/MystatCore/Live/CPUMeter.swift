import Foundation

/// CPU percentages from tick deltas (mean over all cores, 0–100).
public struct CPUMeter: Sendable {
    private var last: (ticks: [CoreTicks], at: Date)?

    public init() {}

    /// `nil` on the first sample, after a long interval, or when a counter goes backwards (the baseline is refreshed).
    public mutating func update(_ ticks: [CoreTicks], at: Date) -> CPUState? {
        defer { last = (ticks, at) }
        guard let prev = last, prev.ticks.count == ticks.count, at.timeIntervalSince(prev.at) <= SampleGap.maxInterval else { return nil }
        var cores: [Double] = [], busyAll = 0.0, sysAll = 0.0, totalAll = 0.0
        for (a, b) in zip(prev.ticks, ticks) {
            guard b.user >= a.user, b.system >= a.system, b.idle >= a.idle, b.nice >= a.nice else { return nil }
            let user = Double(b.user - a.user), sys = Double(b.system - a.system)
            let nice = Double(b.nice - a.nice), idle = Double(b.idle - a.idle)
            let total = user + sys + nice + idle
            cores.append(total > 0 ? (user + sys + nice) / total * 100 : 0)
            busyAll += user + sys + nice; sysAll += sys; totalAll += total
        }
        guard totalAll > 0 else { return nil }
        return CPUState(percent: busyAll / totalAll * 100, systemPercent: sysAll / totalAll * 100, cores: cores, loadAvg: [])
    }
}
