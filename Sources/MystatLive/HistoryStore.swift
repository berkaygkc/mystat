import Foundation
import MystatCore
import SQLite3
import Synchronization

/// Uzun aralık geçmişi (spec §9.4): `~/Library/Application Support/mystat/history.sqlite`.
/// 2 sn'lik örnekler bellekte 10 dk ve 1 sa kovalarına toplanır; kova kapanınca tek satır yazılır.
/// 10 dk ve 1 sa aralıkları `SeriesBuffer`'dadır (bellek). Saklama: 10 dk kovası 7 gün, 1 sa kovası 30 gün.
public final class HistoryStore: Sendable {
    static let tiers: [Int64] = [600, 3600]
    static let keep: [Int64: TimeInterval] = [600: 7 * 86_400, 3600: 30 * 86_400]

    private struct Partial { var bucket: Int64; var sum: Double; var n: Int }
    private struct State {
        var db: OpaquePointer?
        var partial: [Int64: [String: Partial]] = [:]
    }
    private let state: Mutex<State>

    public static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("mystat")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.sqlite")
    }

    public init(url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            throw CocoaError(.fileWriteUnknown)
        }
        for sql in ["PRAGMA journal_mode=WAL", "PRAGMA synchronous=NORMAL",
                    "CREATE TABLE IF NOT EXISTS samples(tier INTEGER, key TEXT, t INTEGER, v REAL, PRIMARY KEY(tier, key, t)) WITHOUT ROWID",
                    "CREATE TABLE IF NOT EXISTS incidents(t INTEGER, kind TEXT, level TEXT, json TEXT)"] {
            sqlite3_exec(db, sql, nil, nil, nil)
        }
        state = Mutex(State(db: db))
    }

    deinit { close() }

    public func close() {
        state.withLock { s in
            if let db = s.db { sqlite3_close_v2(db) }
            s.db = nil
        }
    }

    /// Saklanan anahtarlar; grup ve sensör anahtarları burada yok.
    static func name(_ k: SeriesKey) -> String? {
        switch k {
        case .cpu: "cpu"; case .cpuSystem: "cpuSystem"; case .memUsed: "memUsed"; case .memPressure: "memPressure"
        case .netDown: "netDown"; case .netUp: "netUp"; case .diskRead: "diskRead"; case .diskWrite: "diskWrite"; case .battery: "battery"
        case .dockerCPU: "dockerCPU"; case .dockerMem: "dockerMem"; case .dockerDisk: "dockerDisk"
        case .temp: "temp"; case .fan: "fan"; case .power: "power"; case .gpu: "gpu"
        default: nil
        }
    }

    public func append(_ samples: [(SeriesKey, Double)], at: Date) {
        let t = Int64(at.timeIntervalSince1970)
        state.withLock { s in
            var rows: [(Int64, String, Int64, Double)] = []
            for tier in Self.tiers {
                let bucket = t / tier
                for (key, v) in samples {
                    guard v.isFinite, let k = Self.name(key) else { continue }
                    if var p = s.partial[tier]?[k], p.bucket == bucket {
                        p.sum += v; p.n += 1
                        s.partial[tier]![k] = p
                    } else {
                        if let p = s.partial[tier]?[k], bucket > p.bucket { rows.append((tier, k, p.bucket * tier, p.sum / Double(p.n))) }
                        s.partial[tier, default: [:]][k] = Partial(bucket: bucket, sum: v, n: 1)
                    }
                }
            }
            guard !rows.isEmpty, let db = s.db else { return }
            Self.insert(db, rows)
        }
    }

    private static func insert(_ db: OpaquePointer, _ rows: [(Int64, String, Int64, Double)]) {
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        var st: OpaquePointer?
        if sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO samples VALUES(?, ?, ?, ?)", -1, &st, nil) == SQLITE_OK {
            for (tier, key, t, v) in rows {
                sqlite3_bind_int64(st, 1, tier)
                sqlite3_bind_text(st, 2, key, -1, sqliteTransient)
                sqlite3_bind_int64(st, 3, t)
                sqlite3_bind_double(st, 4, v)
                sqlite3_step(st)
                sqlite3_reset(st)
            }
        }
        sqlite3_finalize(st)
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    /// `.h24`: 10 dk × 144, `.d7`: 1 sa × 168. Aralıktaki ilk veriden "şimdi"ye kadar kova başına bir nokta;
    /// uyku ya da kapalı kalınan kovalar NaN döner (grafik orada boşluk bırakır, düz çizgiyle köprülemez).
    public func series(_ key: SeriesKey, _ range: TimeRange, now: Date) -> [Double] {
        guard let k = Self.name(key), range == .h24 || range == .d7 else { return [] }
        let tier: Int64 = range == .h24 ? 600 : 3600
        let nowBucket = Int64(now.timeIntervalSince1970) / tier
        let first = nowBucket - Int64(range.pointCount) + 1
        let from = first * tier
        return state.withLock { s -> [Double] in
            var pts: [(Int64, Double)] = []
            if let db = s.db {
                var st: OpaquePointer?
                if sqlite3_prepare_v2(db, "SELECT t, v FROM samples WHERE tier = ? AND key = ? AND t >= ? ORDER BY t", -1, &st, nil) == SQLITE_OK {
                    sqlite3_bind_int64(st, 1, tier)
                    sqlite3_bind_text(st, 2, k, -1, sqliteTransient)
                    sqlite3_bind_int64(st, 3, from)
                    while sqlite3_step(st) == SQLITE_ROW { pts.append((sqlite3_column_int64(st, 0) / tier, sqlite3_column_double(st, 1))) }
                }
                sqlite3_finalize(st)
            }
            if let p = s.partial[tier]?[k], p.bucket > (pts.last?.0 ?? .min) { pts.append((p.bucket, p.sum / Double(p.n))) }
            let byBucket = Dictionary(pts.filter { $0.0 >= first && $0.0 <= nowBucket }, uniquingKeysWith: { _, b in b })
            guard let start = byBucket.keys.min() else { return [] }
            return (start...nowBucket).map { byBucket[$0] ?? .nan }
        }
    }

    /// Günlük gidişat (Docker'ın verisi, §9.4): 1 sa kovalarından yerel gün ortalaması. Aralıktaki ilk veri gününden
    /// bugüne en fazla `days` nokta; veri olmayan gün NaN (grafikte boşluk).
    public func daily(_ key: SeriesKey, days: Int, now: Date, calendar: Calendar) -> [Double] {
        guard let k = Self.name(key) else { return [] }
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let from = Int64(first.timeIntervalSince1970)
        let pts = state.withLock { s -> [(Int64, Double)] in
            var pts: [(Int64, Double)] = []
            if let db = s.db {
                var st: OpaquePointer?
                if sqlite3_prepare_v2(db, "SELECT t, v FROM samples WHERE tier = 3600 AND key = ? AND t >= ? ORDER BY t", -1, &st, nil) == SQLITE_OK {
                    sqlite3_bind_text(st, 1, k, -1, sqliteTransient)
                    sqlite3_bind_int64(st, 2, from)
                    while sqlite3_step(st) == SQLITE_ROW { pts.append((sqlite3_column_int64(st, 0), sqlite3_column_double(st, 1))) }
                }
                sqlite3_finalize(st)
            }
            if let p = s.partial[3600]?[k], p.bucket * 3600 > (pts.last?.0 ?? .min) { pts.append((p.bucket * 3600, p.sum / Double(p.n))) }
            return pts
        }
        var sums: [Date: (Double, Int)] = [:]
        for (t, v) in pts where v.isFinite {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(t)))
            sums[day, default: (0, 0)].0 += v
            sums[day, default: (0, 0)].1 += 1
        }
        guard var day = sums.keys.min() else { return [] }
        var out: [Double] = []
        while day <= today {
            out.append(sums[day].map { $0.0 / Double($0.1) } ?? .nan)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    /// Gidişatın farkı: son sonlu gün eksi ilk sonlu gün; 2'den az sonlu gün varsa nil.
    public static func trend(_ daily: [Double]) -> Double? {
        let f = daily.filter(\.isFinite)
        guard f.count >= 2, let a = f.first, let b = f.last else { return nil }
        return b - a
    }

    public func recordIncident(_ i: Incident, at: Date) {
        state.withLock { s in
            guard let db = s.db else { return }
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "INSERT INTO incidents VALUES(?, ?, ?, ?)", -1, &st, nil) == SQLITE_OK {
                let json = "{\"peak\":\(i.peakPercent),\"culprits\":\(i.culpritIDs.debugDescription),\"started\":\"\(i.startedAt)\"}"
                sqlite3_bind_int64(st, 1, Int64(at.timeIntervalSince1970))
                sqlite3_bind_text(st, 2, i.kind.rawValue, -1, sqliteTransient)
                sqlite3_bind_text(st, 3, "\(i.level)", -1, sqliteTransient)
                sqlite3_bind_text(st, 4, json, -1, sqliteTransient)
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    /// Eski kovaları ve olayları siler; WAL dosyasını küçültür.
    public func prune(now: Date) {
        let t = Int64(now.timeIntervalSince1970)
        state.withLock { s in
            guard let db = s.db else { return }
            for (tier, keep) in Self.keep {
                sqlite3_exec(db, "DELETE FROM samples WHERE tier = \(tier) AND t < \(t - Int64(keep))", nil, nil, nil)
            }
            sqlite3_exec(db, "DELETE FROM incidents WHERE t < \(t - 30 * 86_400)", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)
        }
    }

    /// Yarım kovaları o ana kadarki ortalamayla yazar (uygulama kapanırken): yeniden başlatmada son dilim kaybolmaz.
    public func flush() {
        state.withLock { s in
            guard let db = s.db else { return }
            let rows = s.partial.flatMap { tier, keys in keys.map { k, p in (tier, k, p.bucket * tier, p.sum / Double(p.n)) } }
            if !rows.isEmpty { Self.insert(db, rows) }
        }
    }

    // MARK: - Test yardımcıları

    func oldest(tier: Int64) -> Date? {
        state.withLock { s -> Date? in
            guard let db = s.db else { return nil }
            var st: OpaquePointer?
            defer { sqlite3_finalize(st) }
            guard sqlite3_prepare_v2(db, "SELECT MIN(t) FROM samples WHERE tier = \(tier)", -1, &st, nil) == SQLITE_OK,
                  sqlite3_step(st) == SQLITE_ROW, sqlite3_column_type(st, 0) != SQLITE_NULL else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(st, 0)))
        }
    }

    func incidentCount() -> Int {
        state.withLock { s -> Int in
            guard let db = s.db else { return 0 }
            var st: OpaquePointer?
            defer { sqlite3_finalize(st) }
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM incidents", -1, &st, nil) == SQLITE_OK, sqlite3_step(st) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(st, 0))
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
