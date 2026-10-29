import Foundation

/// Bir soketin çekirdekteki alınan bayt sayacı ve sahibi (pcblist_n).
public struct SocketStat: Sendable, Equatable {
    public var handle: UInt64     // çekirdekteki soket adresi: okumalar arasında aynı soketi tanır
    public var pid: Int32
    public var rxBytes: UInt64
    public init(handle: UInt64, pid: Int32, rxBytes: UInt64) { self.handle = handle; self.pid = pid; self.rxBytes = rxBytes }
}

/// Soket sayaçlarından uygulama bazında ↓ hız (spec §6.3 "Kim kullanıyor"). Çekirdek alınan veriyi `receiveFactor`
/// kez sayar (macOS 26'da 2; loopback'te ölçülür). İlk okuma tabandır. İki okuma arasında açılan soketin sayacı tümüyle,
/// kapanan soketinki hiç sayılmaz; sayacı küçülen (tutamacı yeniden kullanılmış) soket yeni sayılır.
public struct SocketRates: Sendable {
    private let factor: Double
    private var previous: [UInt64: UInt64]?
    private var lastTime: TimeInterval = 0

    public init(receiveFactor: Double) { factor = max(1, receiveFactor) }

    /// pid → ↓ MB/s (ondalık); ilk okumada ya da aralık sıfırsa nil.
    public mutating func update(_ stats: [SocketStat], at time: TimeInterval) -> [Int32: Double]? {
        defer { previous = Dictionary(stats.map { ($0.handle, $0.rxBytes) }, uniquingKeysWith: { a, _ in a }); lastTime = time }
        guard let prev = previous, time > lastTime else { return nil }
        let dt = time - lastTime
        var bytes: [Int32: UInt64] = [:]
        for s in stats {
            let before = prev[s.handle] ?? 0
            bytes[s.pid, default: 0] &+= s.rxBytes >= before ? s.rxBytes - before : s.rxBytes
        }
        return bytes.mapValues { Double($0) / factor / dt / 1e6 }
    }
}

/// Uygulama bazında hızlar gruplara.
public enum NetRates {
    /// Grupların `netMBps`'i o anki pid'lerinden toplanır; gruplarda olmayan pid'ler yok sayılır.
    public static func apply(_ rates: [Int32: Double], to groups: inout [ProcessGroup]) {
        for i in groups.indices { groups[i].netMBps = groups[i].pids.reduce(0) { $0 + (rates[$1] ?? 0) } }
    }
}
