import Foundation

/// Arayüz sayaçlarından ağ hızı (MB/s, ondalık) ve bugünkü toplamlar (GB). Bugün yerel gece yarısında sıfırlanır;
/// toplam yeniden başlatmada kaybolmasın diye `today` canlı kaynak tarafından saklanıp geri verilir.
public struct NetMeter: Sendable {
    public struct Today: Sendable, Equatable {
        public var day: String
        public var downGB: Double, upGB: Double
        public init(day: String, downGB: Double, upGB: Double) { self.day = day; self.downGB = downGB; self.upGB = upGB }
    }

    public let primary: String?
    public private(set) var today: Today
    private var last: (rx: UInt64, tx: UInt64, at: Date, names: [String])?

    public init(primary: String?, today: Today = Today(day: "", downGB: 0, upGB: 0)) {
        self.primary = primary
        self.today = today
    }

    /// Birincil arayüz varsa yalnızca o; yoksa `en*` toplamı (VPN `utun` trafiği çift sayılmasın).
    func pick(_ c: [InterfaceCounters]) -> (rx: UInt64, tx: UInt64, names: [String]) {
        let chosen = primary.flatMap { p in c.filter { $0.name == p }.nilIfEmpty } ?? c.filter { $0.name.hasPrefix("en") }
        let sum = chosen.reduce((UInt64(0), UInt64(0))) { ($0.0 &+ $1.rx, $0.1 &+ $1.tx) }
        return (sum.0, sum.1, chosen.map(\.name).sorted())
    }

    public mutating func update(_ c: [InterfaceCounters], at: Date, calendar: Calendar) -> (down: Double, up: Double, todayDown: Double, todayUp: Double)? {
        let now = pick(c)
        defer { last = (now.rx, now.tx, at, now.names) }
        let day = Self.dayKey(at, calendar)
        if today.day != day { today = Today(day: day, downGB: 0, upGB: 0) }
        // Ölçülen arayüzler değiştiyse (VPN kapandı, dock çıktı) sayaçlar karşılaştırılamaz: yeniden başla.
        guard let prev = last, prev.names == now.names else { return nil }
        let dt = at.timeIntervalSince(prev.at)
        guard dt > 0, dt <= SampleGap.maxInterval, now.rx >= prev.rx, now.tx >= prev.tx else { return nil }
        let drx = Double(now.rx - prev.rx), dtx = Double(now.tx - prev.tx)
        today.downGB += drx / 1e9
        today.upGB += dtx / 1e9
        return (drx / 1e6 / dt, dtx / 1e6 / dt, today.downGB, today.upGB)
    }

    static func dayKey(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
