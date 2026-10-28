import Foundation

/// 10 dk (5 sn × 120) ve 1 sa (30 sn × 120) bellek içi seriler; 2 sn'lik örnekler kova ortalamasıyla.
/// Uzun aralıkta (uyku) seriler sıfırlanır: boşluk düz çizgiyle doldurulmaz (Review Focus #1).
/// 24 sa ve 7 gün `HistoryStore`'dadır.
public struct SeriesBuffer: Sendable {
    private struct Key: Hashable { let key: SeriesKey; let range: TimeRange }
    private struct Bucket: Sendable { var index: Int64; var sum: Double; var n: Int }
    private struct Ring: Sendable { var done: [Double] = []; var open: Bucket? }
    static let ranges: [TimeRange] = [.m10, .h1]

    private var rings: [Key: Ring] = [:]
    private var lastAt: Date?

    public init() {}

    public mutating func add(_ key: SeriesKey, _ v: Double, at: Date) {
        guard v.isFinite else { return }
        if let l = lastAt, at.timeIntervalSince(l) > SampleGap.maxInterval { rings.removeAll() }
        lastAt = max(lastAt ?? at, at)
        for range in Self.ranges {
            let idx = Int64((at.timeIntervalSince1970 / range.step).rounded(.down))
            var r = rings[Key(key: key, range: range)] ?? Ring()
            if var o = r.open, o.index == idx {
                o.sum += v; o.n += 1; r.open = o
            } else {
                if let o = r.open, idx > o.index { r.done.append(o.sum / Double(o.n)) }
                if r.done.count > range.pointCount - 1 { r.done.removeFirst(r.done.count - (range.pointCount - 1)) }
                r.open = Bucket(index: idx, sum: v, n: 1)
            }
            rings[Key(key: key, range: range)] = r
        }
    }

    /// En fazla `pointCount` nokta, eskiden yeniye; son nokta henüz kapanmamış kova.
    public func series(_ key: SeriesKey, _ range: TimeRange) -> [Double] {
        guard let r = rings[Key(key: key, range: range)] else { return [] }
        return r.done + (r.open.map { [$0.sum / Double($0.n)] } ?? [])
    }
}

/// Grup başına kısa geçmiş: 10 dk çekirdek ve ayak izi (2 sn), 1 sa disk yazımı (dakikalık kovalar).
/// Detay paneli grafiği, bellek olayının "en çok büyüyen" ve disk olayının "en çok yazan" sorumluları buradan çıkar.
public struct GroupHistory: Sendable {
    static let window: TimeInterval = 600, diskWindow: TimeInterval = 3600
    /// Süreçler kapalı panelde 5 sn'de bir okunur; boşluk eşiği 3 tempo.
    static let gap: TimeInterval = 15

    private struct Point: Sendable { let t: Date; let cores: Double; let mem: Double }
    private var points: [String: [Point]] = [:]
    private var writes: [String: [Int64: UInt64]] = [:]   // dakika → bayt
    private var last: Date?

    public init() {}

    /// `writtenBytes`: bu aralıkta grubun diske yazdığı bayt (fark).
    public mutating func add(_ groups: [ProcessGroup], writtenBytes: [String: UInt64], at: Date) {
        if let l = last, at.timeIntervalSince(l) > Self.gap { points.removeAll(); writes.removeAll() }
        last = at
        for g in groups { points[g.id, default: []].append(Point(t: at, cores: g.cpuCores, mem: g.memoryGB)) }
        let minute = Int64((at.timeIntervalSince1970 / 60).rounded(.down))
        for (id, b) in writtenBytes where b > 0 { writes[id, default: [:]][minute, default: 0] &+= b }
        let cut = at.addingTimeInterval(-Self.window)
        points = points.compactMapValues { ps in
            let kept = ps.drop { $0.t <= cut }
            return kept.isEmpty ? nil : Array(kept)
        }
        let dcut = Int64(((at.timeIntervalSince1970 - Self.diskWindow) / 60).rounded(.down))
        writes = writes.compactMapValues { m in
            let kept = m.filter { $0.key > dcut }
            return kept.isEmpty ? nil : kept
        }
    }

    public func cores(_ id: String) -> [Double] { points[id]?.map(\.cores) ?? [] }

    /// Pencerenin başından bu yana ayak izi değişimi (GB).
    public func memoryGrowthGB() -> [String: Double] {
        points.compactMapValues { ps in ps.count > 1 ? ps.last!.mem - ps.first!.mem : nil }
    }

    /// Son 1 saatte yazılan (GB, ondalık).
    public func diskWrittenGB1h() -> [String: Double] {
        writes.mapValues { Double($0.values.reduce(0, &+)) / 1e9 }
    }
}
