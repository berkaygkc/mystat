import Dispatch
import Foundation
import MystatCore
import MystatProbes
import Synchronization

/// Ağ bölümünün ayrıntıları (spec §6.3, §9.2): yalnızca bölüm görünürken 2 sn'de bir soket sayaçları (uygulama
/// bazında ağ), yönlendiriciye ping ve ≈ 4 sn'de bir bağlantı okuması. Son okuma `latest`'te; `Sampler` her turda
/// yalnızca onu alır. Ping ve bağlantı okuması engelleyicidir: actor kendi seri kuyruğunda çalışır (DockerPoller gibi).
public actor NetDetailPoller {
    public struct Reading: Sendable {
        public var rates: [Int32: Double] = [:]
        public var ratesAt: Date?
        /// Soket sayaçları okunamadıysa ya da loopback ölçümü tutmadıysa false.
        public var perAppAvailable = true
        /// Son 5 ölçümün ortancası (ms).
        public var latencyMs: Double?
        public var link: NetLink?
    }

    public nonisolated let latest = Mutex(Reading())
    /// Son istenen görünürlük: çağrılar sırasız işlense de bu geçerli olur.
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
            // Loopback ölçümü: çekirdeğin alınanı kaç kez saydığı ve kayıt düzeni (her açılışta, ≈ ms).
            let factor = receiveFactor()
            rates = factor.map { SocketRates(receiveFactor: $0) }
            latest.withLock { $0 = Reading(); $0.perAppAvailable = factor != nil }
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

    /// Konum izni verilince: ağın adı bir sonraki tura kalmadan gelsin.
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
                rates = nil   // düzen değişmiş ya da okunamıyor: bu görünürlükte bir daha denenmez
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
