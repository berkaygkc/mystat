import Foundation
import MystatCore
import MystatProbes
import Synchronization
import Testing
@testable import MystatLive

final class FakeNetStream: NetStream {
    let running = Atomic<Bool>(true), stops = Atomic<Int>(0)
    var isRunning: Bool { running.load(ordering: .relaxed) }
    func stop() { stops.add(1, ordering: .relaxed); running.store(false, ordering: .relaxed) }
}

/// Sahte bağlantı, ping ve akış: çağrılar sayılır.
final class NetFakes: Sendable {
    let starts = Atomic<Int>(0), pings = Atomic<Int>(0), links = Atomic<Int>(0)
    let pingValues = Mutex<[Double]>([30, 3, 4])
    let router = Mutex<String?>("192.168.1.1")
    let failStream = Atomic<Bool>(false)
    let lastStream = Mutex<FakeNetStream?>(nil)
    let onSample = Mutex<(@Sendable ([Int32: NetBytes]) -> Void)?>(nil)

    func poller() -> NetDetailPoller {
        NetDetailPoller(
            link: { [self] in
                links.add(1, ordering: .relaxed)
                return NetLink(bsdName: "en0", displayName: "Wi‑Fi", localIP: "192.168.1.42", router: router.withLock { $0 }, dns: [],
                               wifi: nil, linkMbps: nil)
            },
            ping: { [self] _ in pings.add(1, ordering: .relaxed); return pingValues.withLock { $0.isEmpty ? nil : $0.removeFirst() } },
            stream: { [self] cb in
                starts.add(1, ordering: .relaxed)
                if failStream.load(ordering: .relaxed) { return nil }
                let s = FakeNetStream()
                lastStream.withLock { $0 = s }; onSample.withLock { $0 = cb }
                return s
            },
            autoTick: false)
    }
    var startCount: Int { starts.load(ordering: .relaxed) }
    var pingCount: Int { pings.load(ordering: .relaxed) }
}

@Suite struct NetDetailPollerTests {
    @Test func hiddenRunsNothing() async {
        let f = NetFakes(), p = f.poller()
        for _ in 0..<3 { await p.tick() }
        #expect(f.pingCount == 0); #expect(f.startCount == 0)
    }

    @Test func visibleStartsStreamAndPings() async {
        let f = NetFakes(), p = f.poller()
        p.setVisible(true); await p.sync()
        for _ in 0..<3 { await p.tick() }
        #expect(f.startCount == 1); #expect(f.pingCount == 3)
        #expect(p.latest.withLock { $0.latencyMs } == 4)   // 30, 3, 4 → ortanca
        #expect(p.latest.withLock { $0.link?.bsdName } == "en0")
    }

    @Test func samplesBecomeRates() async {
        let f = NetFakes(), p = f.poller()
        p.setVisible(true); await p.sync()
        f.onSample.withLock { $0 }?([7: NetBytes(inBytes: 4_000_000, outBytes: 0)])
        #expect(p.latest.withLock { $0.rates } == [7: 2.0])
        #expect(p.latest.withLock { $0.ratesAt } != nil)
    }

    @Test func hiddenStopsAndClears() async {
        let f = NetFakes(), p = f.poller()
        p.setVisible(true); await p.sync(); await p.tick()
        f.onSample.withLock { $0 }?([7: NetBytes(inBytes: 1_000_000, outBytes: 0)])
        p.setVisible(false); await p.sync()
        #expect(f.lastStream.withLock { $0?.stops.load(ordering: .relaxed) } == 1)
        #expect(p.latest.withLock { $0.rates.isEmpty && $0.latencyMs == nil && $0.link == nil })
        await p.tick()
        #expect(f.pingCount == 1)   // gizliyken tur yok
    }

    @Test func noRouterNoPing() async {
        let f = NetFakes(), p = f.poller()
        f.router.withLock { $0 = nil }
        p.setVisible(true); await p.sync()
        await p.tick(); await p.tick()
        #expect(f.pingCount == 0); #expect(p.latest.withLock { $0.latencyMs } == nil)
    }

    @Test func streamFailureMarksUnavailable() async {
        let f = NetFakes(), p = f.poller()
        f.failStream.store(true, ordering: .relaxed)
        p.setVisible(true); await p.sync()
        #expect(p.latest.withLock { $0.perAppAvailable } == false)
    }

    /// nettop kendiliğinden biterse aynı görünürlükte yeniden başlatılmaz (döngü yok); bir sonraki açılışta başlar.
    @Test func exitedStreamRestartsOnlyOnNextVisible() async {
        let f = NetFakes(), p = f.poller()
        p.setVisible(true); await p.sync()
        f.lastStream.withLock { $0?.running.store(false, ordering: .relaxed) }
        for _ in 0..<3 { await p.tick() }
        #expect(f.startCount == 1)
        #expect(p.latest.withLock { $0.perAppAvailable } == false)
        p.setVisible(false); await p.sync(); p.setVisible(true); await p.sync()
        #expect(f.startCount == 2)
        #expect(p.latest.withLock { $0.perAppAvailable })
    }

    /// Görünürlük çağrıları sırasız işlense de son istenen durum geçerli olur.
    @Test func lastWishWins() async {
        let f = NetFakes(), p = f.poller()
        p.setVisible(true); p.setVisible(false)
        await p.sync(); await p.sync()
        #expect(await p.isVisible == false)
        #expect(f.lastStream.withLock { $0?.isRunning } != true)
    }
}
