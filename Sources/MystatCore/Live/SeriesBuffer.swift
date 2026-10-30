import Foundation

/// In-memory series of 10 min (5 s × 120) and 1 h (30 s × 120); 2 s samples are averaged into buckets.
/// Series are reset after a long interval (sleep): the gap is not filled with a straight line.
/// 24 h and 7 days live in `HistoryStore`.
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

    /// At most `pointCount` points, oldest to newest; the last point is a bucket that has not closed yet.
    public func series(_ key: SeriesKey, _ range: TimeRange) -> [Double] {
        guard let r = rings[Key(key: key, range: range)] else { return [] }
        return r.done + (r.open.map { [$0.sum / Double($0.n)] } ?? [])
    }
}

/// Short history per group: 10 min of cores and footprint (2 s), 1 h of disk writes (per-minute buckets).
/// The detail panel chart, the "fastest growing" culprits of a memory incident and the "top writers" of a disk incident come from here.
public struct GroupHistory: Sendable {
    static let window: TimeInterval = 600, diskWindow: TimeInterval = 3600
    /// Processes are read every 5 s while the panel is closed; the gap threshold is 3 ticks.
    public static let gap: TimeInterval = 15

    private struct Point: Sendable { let t: Date; let cores: Double; let mem: Double; let watts: Double }
    private var points: [String: [Point]] = [:]
    private var writes: [String: [Int64: UInt64]] = [:]   // minute → bytes
    private var last: Date?

    public init() {}

    /// `writtenBytes`: bytes the group wrote to disk in this interval (delta).
    public mutating func add(_ groups: [ProcessGroup], writtenBytes: [String: UInt64], at: Date) {
        if let l = last, at.timeIntervalSince(l) > Self.gap { points.removeAll(); writes.removeAll() }
        last = at
        for g in groups { points[g.id, default: []].append(Point(t: at, cores: g.cpuCores, mem: g.memoryGB, watts: g.watts)) }
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

    /// Footprint change since the start of the window (GB).
    public func memoryGrowthGB() -> [String: Double] {
        points.compactMapValues { ps in ps.count > 1 ? ps.last!.mem - ps.first!.mem : nil }
    }

    /// Average watts over the window (10 min): "Top energy users · last 10 min".
    public func wattsAverage() -> [String: Double] {
        points.mapValues { ps in ps.reduce(0) { $0 + $1.watts } / Double(ps.count) }
    }

    /// Written in the last hour (GB, decimal).
    public func diskWrittenGB1h() -> [String: Double] {
        writes.mapValues { Double($0.values.reduce(0, &+)) / 1e9 }
    }
}
