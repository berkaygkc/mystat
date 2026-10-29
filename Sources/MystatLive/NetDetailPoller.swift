import Dispatch
import Foundation
import MystatCore
import MystatProbes
import Synchronization

/// Ağ bölümünün ayrıntıları (spec §6.3, §9.2): yalnızca bölüm görünürken `nettop` akışı, 2 sn'de bir yönlendiriciye ping
/// ve ≈ 4 sn'de bir bağlantı okuması. Son okuma `latest`'te; `Sampler` her turda yalnızca onu alır. Ping ve bağlantı
/// okuması engelleyicidir: actor kendi seri kuyruğunda çalışır (DockerPoller gibi).
public actor NetDetailPoller {
    public struct Reading: Sendable {
        public var rates: [Int32: Double] = [:]
        public var ratesAt: Date?
        /// `nettop` başlatılamadıysa ya da kendiliğinden bittiyse false.
        public var perAppAvailable = true
        /// Son 5 ölçümün ortancası (ms).
        public var latencyMs: Double?
        public var link: NetLink?
    }

    public nonisolated let latest = Mutex(Reading())
    /// Son istenen görünürlük: çağrılar sırasız işlense de bu geçerli olur.
    private nonisolated let wanted = Mutex(false)
    /// Uygulama kapanırken eşzamanlı durdurabilmek için.
    private nonisolated let streamBox = Mutex<(any NetStream)?>(nil)

    private let queue = DispatchSerialQueue(label: "mystat.net")
    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let readLink: @Sendable () -> NetLink?
    private let ping: @Sendable (String) -> Double?
    private let makeStream: @Sendable (@escaping @Sendable ([Int32: NetBytes]) -> Void) -> (any NetStream)?
    private let autoTick: Bool
    public private(set) var isVisible = false
    private var pings: [Double] = []
    private var turns = 0
    private var loop: Task<Void, Never>?
    static let interval = 2.0

    public init(link: @escaping @Sendable () -> NetLink? = { NetLinkProbe.read() },
                ping: @escaping @Sendable (String) -> Double? = { RouterPing.ping($0) },
                stream: @escaping @Sendable (@escaping @Sendable ([Int32: NetBytes]) -> Void) -> (any NetStream)? = NetDetailPoller.nettop,
                autoTick: Bool = true) {
        self.readLink = link; self.ping = ping; self.makeStream = stream; self.autoTick = autoTick
    }

    /// Başlatılmış `nettop` akışı; başlatılamazsa nil.
    public nonisolated static func nettop(_ onSample: @escaping @Sendable ([Int32: NetBytes]) -> Void) -> (any NetStream)? {
        let s = NettopStream(intervalSeconds: Int(interval), onSample: onSample)
        return s.start() ? s : nil
    }

    /// Ağ bölümü açıldı/kapandı.
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
            let s = makeStream { [self] sample in
                let rates = NetRates.perPid(sample, interval: Self.interval)
                latest.withLock { $0.rates = rates; $0.ratesAt = Date() }
            }
            streamBox.withLock { $0 = s }
            latest.withLock { $0 = Reading(); $0.perAppAvailable = s != nil }
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
            shutdown()
            latest.withLock { $0 = Reading() }
        }
    }

    /// `nettop`'u hemen durdurur (bölüm kapanınca ve uygulama kapanırken).
    public nonisolated func shutdown() {
        let s = streamBox.withLock { box in defer { box = nil }; return box }
        s?.stop()
    }

    func tick() {
        guard isVisible else { return }
        // Kendiliğinden biten akış bu görünürlükte yeniden başlatılmaz (döngü olmasın); bir sonraki açılışta başlar.
        if let s = streamBox.withLock({ $0 }), !s.isRunning { latest.withLock { $0.perAppAvailable = false } }
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
