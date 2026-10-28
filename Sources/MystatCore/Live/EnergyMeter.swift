import Foundation

/// Süreç enerjisi (`ri_energy_nj`) farkı → watt; "En çok enerji harcayanlar" ve ısı/pil olaylarının sorumluları (§7.2.1).
/// `ProcessMeter`'la aynı kurallar: anahtar (pid, başlangıç), aralıkta doğan süreç tam sayılır, kısıtlı süreç ölçülmez.
public struct EnergyMeter: Sendable {
    private struct Key: Hashable { let pid: Int32; let start: Date }
    private var last: (energy: [Key: UInt64], at: Date)?
    public init() {}

    public mutating func update(_ records: [ProcessRecord], at: Date, maxGap: TimeInterval) -> [Int32: Double]? {
        var now: [Key: UInt64] = [:]
        for r in records where !r.restricted { now[Key(pid: r.pid, start: r.start)] = r.energy }
        defer { last = (now, at) }
        guard let p = last else { return nil }
        let dt = at.timeIntervalSince(p.at)
        guard dt > 0, dt <= maxGap else { return nil }
        var out: [Int32: Double] = [:]
        for (k, e) in now {
            if let before = p.energy[k] {
                if e >= before { out[k.pid] = Double(e - before) / 1e9 / dt }
            } else if k.start > p.at {
                out[k.pid] = Double(e) / 1e9 / dt
            }
        }
        return out
    }
}
