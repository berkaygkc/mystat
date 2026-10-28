import Foundation

/// Süreç başına çekirdek: CPU süresi farkı / geçen süre. Anahtar (pid, başlangıç): yeniden kullanılan pid
/// eski sürecin süresini devralmaz (Review Focus #2). İzin verilmeyen süreçler ölçülmez.
public struct ProcessMeter: Sendable {
    private struct Key: Hashable { let pid: Int32; let start: Date }
    private var last: (cpu: [Key: UInt64], at: Date)?

    public init() {}

    /// `maxGap`: kapalı panelde süreçler 5 sn'de bir okunur; eşik 3 tempo.
    public mutating func update(_ records: [ProcessRecord], at: Date, maxGap: TimeInterval = SampleGap.maxInterval) -> [Int32: Double]? {
        var now: [Key: UInt64] = [:]
        for r in records where !r.restricted { now[Key(pid: r.pid, start: r.start)] = r.cpuTime }
        defer { last = (now, at) }
        guard let prev = last else { return nil }
        let dt = at.timeIntervalSince(prev.at)
        guard dt > 0, dt <= maxGap else { return nil }
        var out: [Int32: Double] = [:]
        for (k, cpu) in now {
            guard let before = prev.cpu[k], cpu >= before else { continue }
            out[k.pid] = Double(cpu - before) / 1e9 / dt
        }
        return out
    }
}
