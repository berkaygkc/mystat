import Foundation
import MystatCore
import MystatProbes
import Synchronization
import Testing
@testable import MystatLive

/// Sahte bağlantı, ping, soket sayaçları ve loopback ölçümü: çağrılar sayılır, saat her okumada 2 sn ilerler.
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

@Suite struct NetDetailPollerTests {
    @Test func hiddenRunsNothing() async {
        let f = NetFakes(), p = f.poller()
        for _ in 0..<3 { await p.tick() }
        #expect(f.n(f.pings) == 0); #expect(f.n(f.socketReads) == 0); #expect(f.n(f.factorCalls) == 0)
    }

    @Test func visibleCalibratesAndPings() async {
        let f = NetFakes(), p = f.poller()
        p.setVisible(true); await p.sync()
        for _ in 0..<3 { await p.tick() }
        #expect(f.n(f.factorCalls) == 1); #expect(f.n(f.pings) == 3); #expect(f.n(f.socketReads) == 3)
        #expect(p.latest.withLock { $0.latencyMs } == 4)   // 30, 3, 4 → ortanca
        #expect(p.latest.withLock { $0.link?.bsdName } == "en0")
    }

    /// 2 sn'de 8 MB sayaç farkı, çekirdek iki kez sayıyor → 2 MB/s.
    @Test func socketsBecomeRates() async {
        let f = NetFakes(), p = f.poller()
        f.sockets.withLock { $0 = [[SocketStat(handle: 1, pid: 7, rxBytes: 0)], [SocketStat(handle: 1, pid: 7, rxBytes: 8_000_000)]] }
        p.setVisible(true); await p.sync()
        await p.tick(); await p.tick()
        #expect(p.latest.withLock { $0.rates } == [7: 2.0])
        #expect(p.latest.withLock { $0.ratesAt } != nil)
    }

    @Test func hiddenStopsAndClears() async {
        let f = NetFakes(), p = f.poller()
        f.sockets.withLock { $0 = [[SocketStat(handle: 1, pid: 7, rxBytes: 0)], [SocketStat(handle: 1, pid: 7, rxBytes: 4_000_000)]] }
        p.setVisible(true); await p.sync(); await p.tick(); await p.tick()
        p.setVisible(false); await p.sync()
        #expect(p.latest.withLock { $0.rates.isEmpty && $0.latencyMs == nil && $0.link == nil })
        await p.tick()
        #expect(f.n(f.socketReads) == 2); #expect(f.n(f.pings) == 2)   // gizliyken tur yok
    }

    @Test func noRouterNoPing() async {
        let f = NetFakes(), p = f.poller()
        f.router.withLock { $0 = nil }
        p.setVisible(true); await p.sync()
        await p.tick(); await p.tick()
        #expect(f.n(f.pings) == 0); #expect(p.latest.withLock { $0.latencyMs } == nil)
    }

    /// Loopback ölçümü tutmadı (düzen değişmiş ya da oran tuhaf): liste "okunamadı", sayaçlar hiç okunmaz.
    @Test func calibrationFailureMarksUnavailable() async {
        let f = NetFakes(), p = f.poller()
        f.factor.withLock { $0 = nil }
        p.setVisible(true); await p.sync(); await p.tick()
        #expect(p.latest.withLock { $0.perAppAvailable } == false)
        #expect(f.n(f.socketReads) == 0)
    }

    /// Sayaçlar okunamadı: bu görünürlükte bir daha denenmez (her turda boşuna sysctl yok), bir sonraki açılışta yeniden.
    @Test func socketReadFailureMarksUnavailable() async {
        let f = NetFakes(), p = f.poller()
        f.sockets.withLock { $0 = [nil] }
        p.setVisible(true); await p.sync()
        await p.tick(); await p.tick()
        #expect(p.latest.withLock { $0.perAppAvailable } == false)
        #expect(f.n(f.socketReads) == 1)
        p.setVisible(false); await p.sync(); p.setVisible(true); await p.sync()
        #expect(f.n(f.factorCalls) == 2); #expect(p.latest.withLock { $0.perAppAvailable })
    }

    /// Görünürlük çağrıları sırasız işlense de son istenen durum geçerli olur.
    @Test func lastWishWins() async {
        let f = NetFakes(), p = f.poller()
        p.setVisible(true); p.setVisible(false)
        await p.sync(); await p.sync()
        #expect(await p.isVisible == false)
        #expect(f.n(f.factorCalls) == 0)
    }
}
