import Dispatch
import Foundation
import MystatCore
import MystatProbes
import Synchronization

/// Docker'ı kendi temposunda okur (spec §9.2) ve son okumayı `latest`'te tutar; `Sampler` her turda yalnızca onu alır.
/// Soket G/Ç'si engelleyicidir (zaman aşımı 3 sn): actor kendi seri kuyruğunda çalışır, Swift'in ortak iş parçacıklarını
/// ve ölçüm döngüsünü bekletmez.
public actor DockerPoller {
    public struct Reading: Sendable {
        public var running = false
        public var containers: [Container] = []
        public var vmMemoryGB = 0.0, vmCores = 0
        public var disk: DockerDisk?
        public var diskAt: Date?
    }

    /// Ölçüm döngüsünün okuduğu son durum.
    public nonisolated let latest = Mutex(Reading())
    /// Panel ya da monitör açık mı (tempo 5 sn / 15 sn).
    public nonisolated let interest = Mutex(false)

    private let queue = DispatchSerialQueue(label: "mystat.docker")
    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let api: any DockerAPI
    private let rawFile: @Sendable () -> Double?
    private var meter = DockerMeter()
    private var connected = false
    private var timeouts = 0
    private var rawGB: Double?
    private var lastRequest: Date?
    private var loop: Task<Void, Never>?
    /// Süren eylemler: actor çağrıları sıraya girdiği için çift tıklama denetimi actor'a girmeden yapılır.
    private nonisolated let inFlight = Mutex(Set<DockerAction>())

    public init(api: some DockerAPI = DockerClient(), rawFile: @escaping @Sendable () -> Double? = { DockerDiskFile.allocatedGB() }) {
        self.api = api
        self.rawFile = rawFile
    }

    public func start() {
        loop?.cancel()
        loop = Task {
            while !Task.isCancelled {
                poll(at: Date())
                let r = latest.withLock { $0 }
                try? await Task.sleep(for: .seconds(Self.delay(running: r.running, containerCount: r.containers.count,
                                                                interest: interest.withLock { $0 })))
            }
        }
    }

    public func stop() { loop?.cancel() }

    /// Docker yok: 30 sn; hiç container yok (Resource Saver, sanal makineyi uyandırma): 60 sn; ilgi varken 5, yokken 15 sn.
    public nonisolated static func delay(running: Bool, containerCount: Int, interest: Bool) -> TimeInterval {
        guard running else { return 30 }
        guard containerCount > 0 else { return 60 }
        return interest ? 5 : 15
    }

    public func poll(at now: Date) {
        do {
            if !connected {
                let info = try api.info()
                latest.withLock { $0.vmCores = info.ncpu; $0.vmMemoryGB = Double(info.memTotal) / 1_073_741_824 }
                connected = true
            }
            let list = try api.containers()
            var stats: [DockerStatsRaw] = [], gone = Set<String>()
            for c in list {
                do { stats.append(try api.stats(c.id)) } catch DockerError.http { gone.insert(c.id) }   // liste ile istatistik arasında silindi
            }
            let containers = meter.containers(list.filter { !gone.contains($0.id) }, stats: stats)
            timeouts = 0
            latest.withLock { $0.running = true; $0.containers = containers }
            let diskAt = latest.withLock { $0.diskAt }
            if !containers.isEmpty, diskAt.map({ now.timeIntervalSince($0) >= 600 }) ?? true { refreshDisk(at: now) }
        } catch DockerError.timeout {
            timeouts += 1
            if timeouts >= 2 { down() }
        } catch {
            down()
        }
    }

    /// Docker bölümü açıldı: disk ve sanal disk dosyası (izin istemi bağlamında çıksın); 60 sn'den sık değil.
    public func requestDisk(at now: Date) {
        guard lastRequest.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        lastRequest = now
        rawGB = rawFile()
        if latest.withLock({ $0.running }) { refreshDisk(at: now) }
    }

    /// §7.4 eylemleri. Aynı eylem sürerken ikinci istek gönderilmez.
    public nonisolated func perform(_ action: DockerAction) async -> DockerActionOutcome {
        guard inFlight.withLock({ $0.insert(action).inserted }) else { return .failed("Bu işlem zaten sürüyor") }
        defer { inFlight.withLock { _ = $0.remove(action) } }
        return await run(action)
    }

    private func run(_ action: DockerAction) -> DockerActionOutcome {
        func filters(_ json: String) -> String { "?filters=" + (json.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") }
        let (path, timeout): (String, TimeInterval) = switch action {
        case .restart(let id, _): ("/containers/\(id)/restart?t=10", 30)
        case .stop(let id, _): ("/containers/\(id)/stop?t=10", 30)
        case .pruneAnonymousVolumes: ("/volumes/prune", 120)                         // API ≥ 1.42: yalnızca adsızlar
        case .pruneAllVolumes: ("/volumes/prune" + filters(#"{"all":["true"]}"#), 120)
        case .pruneImages: ("/images/prune" + filters(#"{"dangling":["false"]}"#), 120)
        }
        let outcome: DockerActionOutcome
        do {
            let r = try api.post(path, timeout: timeout)
            switch r.status {
            case 200..<300, 304:
                let reclaimed = (try? JSONDecoder().decode(Reclaimed.self, from: r.body)).map { Double($0.SpaceReclaimed ?? 0) / 1e9 }
                outcome = .done(reclaimedGB: action.isPrune ? reclaimed ?? 0 : nil)
            case 404: outcome = .failed("Container bulunamadı")
            default: outcome = .failed("Docker isteği reddetti (\(r.status))")
            }
        } catch DockerError.notRunning {
            return .failed("Docker çalışmıyor")
        } catch DockerError.timeout {
            return .failed("Docker cevap vermedi")
        } catch {
            return .failed("Docker isteği başarısız")
        }
        let now = Date()
        poll(at: now)
        if action.isPrune { refreshDisk(at: now) }
        return outcome
    }

    private struct Reclaimed: Decodable { let SpaceReclaimed: Int64? }

    private func refreshDisk(at now: Date) {
        guard let df = try? api.diskUsage() else { return }
        let disk = DockerMeter.disk(df, rawGB: rawGB)
        latest.withLock { $0.disk = disk; $0.diskAt = now }
    }

    private func down() {
        connected = false
        timeouts = 0
        meter = DockerMeter()
        latest.withLock { $0 = Reading() }
    }
}
