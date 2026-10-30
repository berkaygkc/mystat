import Dispatch
import Foundation
import MystatCore
import MystatProbes
import Synchronization

/// Network section details: only while the section is visible, socket counters every 2 s (per-app
/// network), a ping to the router, and a link reading about every 4 s. The latest reading is in `latest`; `Sampler` picks
/// up only that each round. Ping and link reading are blocking: the actor runs on its own serial queue (like DockerPoller).
public actor NetDetailPoller {
    public struct Reading: Sendable {
        public var rates: [Int32: Double] = [:]
        public var ratesAt: Date?
        /// False if the socket counters could not be read or the loopback measurement did not check out.
        public var perAppAvailable = true
        /// Median of the last 5 measurements (ms).
        public var latencyMs: Double?
        public var link: NetLink?
    }

    public nonisolated let latest = Mutex(Reading())
    /// Last requested visibility: holds even if calls are processed out of order.
    private nonisolated let wanted = Mutex(false)

    private let queue = DispatchSerialQueue(label: "mystat.net")
    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let readLink: @Sendable () -> NetLink?
    private let ping: @Sendable (String) -> Double?
    private let readSockets: @Sendable () -> [SocketStat]?
    private let receiveFactor: @Sendable () -> Double?
    private let clock: @Sendable () -> TimeInterval
    private let autoTick: Bool
    public private(set) var isVisible = false
    private var rates: SocketRates?
    private var pings: [Double] = []
    private var turns = 0
    private var loop: Task<Void, Never>?
    static let interval = 2.0

    public init(link: @escaping @Sendable () -> NetLink? = { NetLinkProbe.read() },
                ping: @escaping @Sendable (String) -> Double? = { RouterPing.ping($0) },
                sockets: @escaping @Sendable () -> [SocketStat]? = { SocketStatsProbe.read() },
                receiveFactor: @escaping @Sendable () -> Double? = { SocketStatsProbe.receiveFactor() },
                clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                autoTick: Bool = true) {
        self.readLink = link; self.ping = ping; self.readSockets = sockets; self.receiveFactor = receiveFactor
        self.clock = clock; self.autoTick = autoTick
    }

    /// Network section opened/closed.
    public nonisolated func setVisible(_ visible: Bool) {
        wanted.withLock { $0 = visible }
        Task { await self.sync() }
    }

    func sync() {
        let v = wanted.withLock { $0 }
        guard v != isVisible else { return }
        isVisible = v
        if v {
            pings = []; turns = 0
            // Loopback measurement: how many times the kernel counts received bytes, and the record layout (on every open, ≈ ms).
            let factor = receiveFactor()
            rates = factor.map { SocketRates(receiveFactor: $0) }
            // Baseline immediately: rates are ready on the first round (≈ 2 s later); until then the list shows "Measuring…".
            if rates != nil {
                if let stats = readSockets() { _ = rates!.update(stats, at: clock()) } else { rates = nil }
            }
            let available = rates != nil
            latest.withLock { $0 = Reading(); $0.perAppAvailable = available }
            if autoTick {
                loop = Task { [weak self] in
                    while !Task.isCancelled {
                        await self?.tick()
                        try? await Task.sleep(for: .seconds(Self.interval))
                    }
                }
            }
        } else {
            loop?.cancel(); loop = nil
            rates = nil
            latest.withLock { $0 = Reading() }
        }
    }

    /// When location permission is granted: the network name arrives without waiting for the next round.
    public nonisolated func refreshLink() { Task { await self.readLinkNow() } }

    func readLinkNow() {
        guard isVisible else { return }
        let link = readLink()
        latest.withLock { $0.link = link }
    }

    func tick() {
        guard isVisible else { return }
        if rates != nil {
            if let stats = readSockets() {
                if let r = rates!.update(stats, at: clock()) { latest.withLock { $0.rates = r; $0.ratesAt = Date() } }
            } else {
                rates = nil   // layout changed or unreadable: not retried for this visibility
                latest.withLock { $0.perAppAvailable = false; $0.rates = [:]; $0.ratesAt = nil }
            }
        }
        var link = latest.withLock { $0.link }
        if turns % 2 == 0 || link == nil { link = readLink() }
        turns += 1
        if let router = link?.router {
            if let ms = ping(router) { pings.append(ms); if pings.count > 5 { pings.removeFirst(pings.count - 5) } }
        } else {
            pings = []
        }
        let median = pings.isEmpty ? nil : pings.sorted()[pings.count / 2]
        latest.withLock { $0.link = link; $0.latencyMs = median }
    }
}
