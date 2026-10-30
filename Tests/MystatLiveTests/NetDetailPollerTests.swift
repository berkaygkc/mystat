import Foundation
import MystatCore
import MystatProbes
import Synchronization
import MystatTestSupport
import Testing
@testable import MystatLive

/// Fake connection, ping, socket counters and loopback measurement: calls are counted, and the clock advances 2 s on each read.
final class NetFakes: Sendable {
    let factorCalls = Atomic<Int>(0), pings = Atomic<Int>(0), links = Atomic<Int>(0), socketReads = Atomic<Int>(0)
    let pingValues = Mutex<[Double]>([30, 3, 4])
    let router = Mutex<String?>("192.168.1.1")
    let factor = Mutex<Double?>(2)
    let sockets = Mutex<[[SocketStat]?]>([])
    let time = Mutex<TimeInterval>(100)

    func poller() -> NetDetailPoller {
        NetDetailPoller(
            link: { [self] in
                links.add(1, ordering: .relaxed)
                return NetLink(bsdName: "en0", displayName: "Wi‑Fi", localIP: "192.168.1.42", router: router.withLock { $0 }, dns: [],
                               wifi: nil, linkMbps: nil)
            },
            ping: { [self] _ in pings.add(1, ordering: .relaxed); return pingValues.withLock { $0.isEmpty ? nil : $0.removeFirst() } },
            sockets: { [self] in socketReads.add(1, ordering: .relaxed); return sockets.withLock { $0.isEmpty ? [] : $0.removeFirst() } },
            receiveFactor: { [self] in factorCalls.add(1, ordering: .relaxed); return factor.withLock { $0 } },
            clock: { [self] in time.withLock { $0 += 2; return $0 } },
            autoTick: false)
    }
    func n(_ a: borrowing Atomic<Int>) -> Int { a.load(ordering: .relaxed) }
}

@Suite(.language("tr")) struct NetDetailPollerTests {
    @Test func hiddenRunsNothing() async {
        let f = NetFakes(), p = f.poller()
        for _ in 0..<3 { await p.tick() }
        #expect(f.n(f.pings) == 0); #expect(f.n(f.socketReads) == 0); #expect(f.n(f.factorCalls) == 0)
    }

    @Test func visibleCalibratesAndPings() async {
        let f = NetFakes(), p = f.poller()
        p.setVisible(true); await p.sync()
        for _ in 0..<3 { await p.tick() }
        #expect(f.n(f.factorCalls) == 1); #expect(f.n(f.pings) == 3); #expect(f.n(f.socketReads) == 4)   // baseline + 3 rounds
        #expect(p.latest.withLock { $0.latencyMs } == 4)   // 30, 3, 4 → median
        #expect(p.latest.withLock { $0.link?.bsdName } == "en0")
    }

    /// An 8 MB counter delta in 2 s with the kernel counting twice → 2 MB/s.
    @Test func socketsBecomeRates() async {
        let f = NetFakes(), p = f.poller()
        f.sockets.withLock { $0 = [[SocketStat(generation: 1, pid: 7, rxBytes: 0)], [SocketStat(generation: 1, pid: 7, rxBytes: 8_000_000)]] }
        p.setVisible(true); await p.sync()
        await p.tick()
        #expect(p.latest.withLock { $0.rates } == [7: 2.0])
        #expect(p.latest.withLock { $0.ratesAt } != nil)
    }

    @Test func hiddenStopsAndClears() async {
        let f = NetFakes(), p = f.poller()
        f.sockets.withLock { $0 = [[SocketStat(generation: 1, pid: 7, rxBytes: 0)], [SocketStat(generation: 1, pid: 7, rxBytes: 4_000_000)]] }
        p.setVisible(true); await p.sync(); await p.tick(); await p.tick()
        p.setVisible(false); await p.sync()
        #expect(p.latest.withLock { $0.rates.isEmpty && $0.latencyMs == nil && $0.link == nil })
        await p.tick()
        #expect(f.n(f.socketReads) == 3); #expect(f.n(f.pings) == 2)   // baseline + 2 rounds; no rounds while hidden
    }

    @Test func noRouterNoPing() async {
        let f = NetFakes(), p = f.poller()
        f.router.withLock { $0 = nil }
        p.setVisible(true); await p.sync()
        await p.tick(); await p.tick()
        #expect(f.n(f.pings) == 0); #expect(p.latest.withLock { $0.latencyMs } == nil)
    }

    /// The loopback measurement did not hold (layout changed or the ratio is odd): the list says "unreadable" and the counters are never read.
    @Test func calibrationFailureMarksUnavailable() async {
        let f = NetFakes(), p = f.poller()
        f.factor.withLock { $0 = nil }
        p.setVisible(true); await p.sync(); await p.tick()
        #expect(p.latest.withLock { $0.perAppAvailable } == false)
        #expect(f.n(f.socketReads) == 0)
    }

    /// Counters were unreadable: it is not retried at this visibility (no pointless sysctl every round), only on the next open.
    @Test func socketReadFailureMarksUnavailable() async {
        let f = NetFakes(), p = f.poller()
        f.sockets.withLock { $0 = [nil] }
        p.setVisible(true); await p.sync()   // baseline unreadable
        await p.tick(); await p.tick()
        #expect(p.latest.withLock { $0.perAppAvailable } == false)
        #expect(f.n(f.socketReads) == 1)
        p.setVisible(false); await p.sync(); p.setVisible(true); await p.sync()
        #expect(f.n(f.factorCalls) == 2); #expect(p.latest.withLock { $0.perAppAvailable })
    }

    /// Even if visibility calls are processed out of order, the last requested state wins.
    @Test func lastWishWins() async {
        let f = NetFakes(), p = f.poller()
        p.setVisible(true); p.setVisible(false)
        await p.sync(); await p.sync()
        #expect(await p.isVisible == false)
        #expect(f.n(f.factorCalls) == 0)
    }

    /// The baseline is taken when the section opens: rates are ready on the first round (so that "nobody is using it" is not shown for 2–4 s after opening).
    @Test func baselineTakenOnOpen() async {
        let f = NetFakes(), p = f.poller()
        f.sockets.withLock { $0 = [[SocketStat(generation: 1, pid: 7, rxBytes: 0)], [SocketStat(generation: 1, pid: 7, rxBytes: 8_000_000)]] }
        p.setVisible(true); await p.sync()
        #expect(f.n(f.socketReads) == 1)
        await p.tick()
        #expect(p.latest.withLock { $0.rates } == [7: 2.0])
    }

    /// If counters become unreadable after the baseline is taken, the list says "unreadable" and is not retried at this visibility.
    @Test func tickReadFailureMarksUnavailable() async {
        let f = NetFakes(), p = f.poller()
        f.sockets.withLock { $0 = [[SocketStat(generation: 1, pid: 7, rxBytes: 0)], nil] }
        p.setVisible(true); await p.sync()
        #expect(p.latest.withLock { $0.perAppAvailable })
        await p.tick(); await p.tick()
        #expect(p.latest.withLock { $0.perAppAvailable } == false)
        #expect(f.n(f.socketReads) == 2)
    }
}
