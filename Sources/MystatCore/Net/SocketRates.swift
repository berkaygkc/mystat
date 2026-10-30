import Foundation

/// A socket's received-byte counter in the kernel, and its owner (pcblist_n).
public struct SocketStat: Sendable, Equatable {
    /// Generation number of the kernel socket (unique, never reused). 0 for Network.framework's user-space
    /// flows: they appear in the list without a handle and are recognized by their ports.
    public var generation: UInt64
    public var pid: Int32
    public var rxBytes: UInt64
    public var proto: UInt8
    public var localPort: UInt16, foreignPort: UInt16

    public init(generation: UInt64, pid: Int32, rxBytes: UInt64, proto: UInt8 = 6, localPort: UInt16 = 0, foreignPort: UInt16 = 0) {
        self.generation = generation; self.pid = pid; self.rxBytes = rxBytes; self.proto = proto
        self.localPort = localPort; self.foreignPort = foreignPort
    }

    /// User-space flow: counts received bytes once (kernel sockets count them twice; measured).
    public var isUserSpaceFlow: Bool { generation == 0 }

    enum Key: Hashable { case kernel(UInt64), flow(pid: Int32, proto: UInt8, local: UInt16, foreign: UInt16) }
    var key: Key { isUserSpaceFlow ? .flow(pid: pid, proto: proto, local: localPort, foreign: foreignPort) : .kernel(generation) }
}

/// Per-app ↓ rate from socket counters (the "Who's using it" list). Kernel sockets count received data
/// `receiveFactor` times (2 on macOS 26; measured on loopback); user-space flows count it once. The first reading is the baseline.
/// A socket opened between two readings counts in full, one that closed counts not at all; a socket whose counter shrinks is treated as new.
public struct SocketRates: Sendable {
    private let factor: Double
    private var previous: [SocketStat.Key: UInt64]?
    private var lastTime: TimeInterval = 0

    public init(receiveFactor: Double) { factor = max(1, receiveFactor) }

    /// pid → ↓ MB/s (decimal); nil on the first reading or if the interval is zero.
    public mutating func update(_ stats: [SocketStat], at time: TimeInterval) -> [Int32: Double]? {
        defer { previous = Dictionary(stats.map { ($0.key, $0.rxBytes) }, uniquingKeysWith: { a, b in a &+ b }); lastTime = time }
        guard let prev = previous, time > lastTime else { return nil }
        let dt = time - lastTime
        var current: [SocketStat.Key: (pid: Int32, rx: UInt64, divisor: Double)] = [:]
        for s in stats {   // several records with the same identity (rare) are summed
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

/// Per-app rates, mapped onto groups.
public enum NetRates {
    /// Each group's `netMBps` is summed from its current pids; pids that are in no group are ignored.
    public static func apply(_ rates: [Int32: Double], to groups: inout [ProcessGroup]) {
        for i in groups.indices { groups[i].netMBps = groups[i].pids.reduce(0) { $0 + (rates[$1] ?? 0) } }
    }
}
