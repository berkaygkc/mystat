import Foundation

/// Süreç başına çekirdek: CPU süresi farkı / geçen süre. Anahtar (pid, başlangıç): yeniden kullanılan pid
/// eski sürecin süresini devralmaz (Review Focus #2). İzin verilmeyen süreçler ölçülmez.
/// Kısa ömürlü işler (derleyici, test koşucusu) "macOS" payına düşmesin diye: aralıkta doğan sürecin tüm süresi,
/// ölüp toplanan çocukların süresi de (`childCPUTime` farkı) ebeveyne yazılır; önceden sayılmış kısmı düşülerek.
public struct ProcessMeter: Sendable {
    private struct Key: Hashable { let pid: Int32; let start: Date }
    private struct Reading { let cpu: UInt64, child: UInt64, ppid: Int32 }
    private var last: (procs: [Key: Reading], at: Date)?
    /// Ölen çocuğun önceden sayılmış süresi; ebeveyn onu henüz toplamadıysa sonraki turda düşülür.
    private var owed: [Key: UInt64] = [:]
    private let cores: Int

    public init(cores: Int = ProcessInfo.processInfo.activeProcessorCount) { self.cores = cores }

    /// `maxGap`: kapalı panelde süreçler 5 sn'de bir okunur; eşik 3 tempo.
    public mutating func update(_ records: [ProcessRecord], at: Date, maxGap: TimeInterval = SampleGap.maxInterval) -> [Int32: Double]? {
        var now: [Key: Reading] = [:]
        for r in records where !r.restricted { now[Key(pid: r.pid, start: r.start)] = Reading(cpu: r.cpuTime, child: r.childCPUTime, ppid: r.ppid) }
        defer { last = (now, at) }
        guard let prev = last else { return nil }
        let dt = at.timeIntervalSince(prev.at)
        guard dt > 0, dt <= maxGap else { owed = [:]; return nil }
        var counted: [Int32: UInt64] = [:]
        for (k, r) in prev.procs where now[k] == nil { counted[r.ppid, default: 0] &+= r.cpu &+ r.child }
        let ceiling = UInt64(dt * 1e9 * Double(cores))
        var out: [Int32: Double] = [:], nextOwed: [Key: UInt64] = [:]
        for (k, r) in now {
            var used: UInt64
            if let b = prev.procs[k] {
                guard r.cpu >= b.cpu else { continue }
                used = r.cpu - b.cpu
                let reaped = r.child >= b.child ? r.child - b.child : 0
                let debt = (owed[k] ?? 0) &+ (counted[k.pid] ?? 0)
                if reaped >= debt { used &+= reaped - debt } else { nextOwed[k] = debt - reaped }
            } else if k.start > prev.at {
                used = r.cpu &+ r.child                                    // bu aralıkta doğdu
            } else { continue }
            out[k.pid] = Double(min(used, ceiling)) / 1e9 / dt
        }
        owed = nextOwed
        return out
    }
}
