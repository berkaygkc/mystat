import Foundation

/// Sensör değerleri: akla yatmayan okumalar (−9.201, 0, 3,4, 150 üstü, NaN) ortalamaya girmez.
public enum SensorMeter {
    static let plausible = 10.0...120.0

    public static func average(_ values: [Double]) -> Double? {
        let ok = values.filter { $0.isFinite && plausible.contains($0) }
        return ok.isEmpty ? nil : ok.reduce(0, +) / Double(ok.count)
    }
}

/// IOReport birikimli joule → watt. İlk okumada, uzun aralıktan (uyku) sonra, sayaç geri gidince ya da akla yatmayan
/// değerde nil: sıçrama gösterilmez.
public struct PowerMeter: Sendable {
    private var last: (e: EnergyCounters, at: Date)?
    public init() {}

    public mutating func update(_ e: EnergyCounters, at: Date) -> (cpu: Double, gpu: Double)? {
        defer { last = (e, at) }
        guard let p = last else { return nil }
        let dt = at.timeIntervalSince(p.at)
        guard dt > 0, dt <= SampleGap.maxInterval, e.cpuJ >= p.e.cpuJ, e.gpuJ >= p.e.gpuJ else { return nil }
        let cpu = (e.cpuJ - p.e.cpuJ) / dt, gpu = (e.gpuJ - p.e.gpuJ) / dt
        guard cpu <= 500, gpu <= 500 else { return nil }
        return (cpu, gpu)
    }
}

/// İstemci GPU süresi farkı → uygulama başına yüzde (%100 = GPU'nun tamamı bir uygulamada). Anahtar (pid, ad): aynı pid
/// başka uygulamaya geçerse eskisinin sayacı devralınmaz. Ad çekirdekte kırpılmış olabilir; tamamlamak örnekleyicinin işi.
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
        guard dt > 0, dt <= SampleGap.maxInterval else { return nil }
        var byName: [String: Double] = [:]
        for (k, ns) in now {
            guard let before = p.ns[k], ns > before else { continue }
            byName[k.name, default: 0] += Double(ns - before) / (dt * 1e9) * 100
        }
        return byName.map { ($0.key, $0.value) }.sorted { $0.percent > $1.percent }
    }
}
