import Foundation

/// Bir soketin çekirdekteki alınan bayt sayacı ve sahibi (pcblist_n).
public struct SocketStat: Sendable, Equatable {
    /// Çekirdek soketinin kuşak numarası (benzersiz, yeniden kullanılmaz). Network.framework'ün kullanıcı alanı
    /// akışlarında 0: bunlar listede tutamaçsız görünür ve bağlantı noktalarıyla tanınır.
    public var generation: UInt64
    public var pid: Int32
    public var rxBytes: UInt64
    public var proto: UInt8
    public var localPort: UInt16, foreignPort: UInt16

    public init(generation: UInt64, pid: Int32, rxBytes: UInt64, proto: UInt8 = 6, localPort: UInt16 = 0, foreignPort: UInt16 = 0) {
        self.generation = generation; self.pid = pid; self.rxBytes = rxBytes; self.proto = proto
        self.localPort = localPort; self.foreignPort = foreignPort
    }

    /// Kullanıcı alanı akışı: alınanı bir kez sayar (çekirdek soketleri iki kez; ölçüldü).
    public var isUserSpaceFlow: Bool { generation == 0 }

    enum Key: Hashable { case kernel(UInt64), flow(pid: Int32, proto: UInt8, local: UInt16, foreign: UInt16) }
    var key: Key { isUserSpaceFlow ? .flow(pid: pid, proto: proto, local: localPort, foreign: foreignPort) : .kernel(generation) }
}

/// Soket sayaçlarından uygulama bazında ↓ hız (spec §6.3 "Kim kullanıyor"). Çekirdek soketleri alınan veriyi
/// `receiveFactor` kez sayar (macOS 26'da 2; loopback'te ölçülür); kullanıcı alanı akışları bir kez. İlk okuma tabandır.
/// İki okuma arasında açılan soketin sayacı tümüyle, kapanan soketinki hiç sayılmaz; sayacı küçülen soket yeni sayılır.
public struct SocketRates: Sendable {
    private let factor: Double
    private var previous: [SocketStat.Key: UInt64]?
    private var lastTime: TimeInterval = 0

    public init(receiveFactor: Double) { factor = max(1, receiveFactor) }

    /// pid → ↓ MB/s (ondalık); ilk okumada ya da aralık sıfırsa nil.
    public mutating func update(_ stats: [SocketStat], at time: TimeInterval) -> [Int32: Double]? {
        defer { previous = Dictionary(stats.map { ($0.key, $0.rxBytes) }, uniquingKeysWith: { a, b in a &+ b }); lastTime = time }
        guard let prev = previous, time > lastTime else { return nil }
        let dt = time - lastTime
        var current: [SocketStat.Key: (pid: Int32, rx: UInt64, divisor: Double)] = [:]
        for s in stats {   // aynı kimlikte birden çok kayıt (nadir) toplanır
            let c = current[s.key]
            current[s.key] = (s.pid, (c?.rx ?? 0) &+ s.rxBytes, s.isUserSpaceFlow ? 1 : factor)
        }
        var rates: [Int32: Double] = [:]
        for (key, c) in current {
            let before = prev[key] ?? 0
            let delta = c.rx >= before ? c.rx - before : c.rx
            rates[c.pid, default: 0] += Double(delta) / c.divisor / dt / 1e6
        }
        return rates
    }
}

/// Uygulama bazında hızlar gruplara.
public enum NetRates {
    /// Grupların `netMBps`'i o anki pid'lerinden toplanır; gruplarda olmayan pid'ler yok sayılır.
    public static func apply(_ rates: [Int32: Double], to groups: inout [ProcessGroup]) {
        for i in groups.indices { groups[i].netMBps = groups[i].pids.reduce(0) { $0 + (rates[$1] ?? 0) } }
    }
}
