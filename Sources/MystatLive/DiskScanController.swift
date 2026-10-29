import Darwin
import Foundation
import MystatCore
import MystatProbes
import Observation
import Synchronization

/// Ev klasörü taraması (spec §6.4): yalnızca elle başlar, tarama sürerken ağaç canlı büyür, sonuç 1 saat geçerlidir.
/// Süre boyunca `~/Library/Application Support/mystat/` altında sıkıştırılmış önbellektedir; süre dolunca silinir.
/// Disk bölümü kapalıyken ağaç bellekte tutulmaz (tarama sürmüyorsa).
@MainActor @Observable
public final class DiskScanController {
    public private(set) var phase: ScanPhase = .none
    public private(set) var tree: DiskTree = DiskScanController.emptyTree()
    /// Son taramada okunamayan klasörler (Tam Disk Erişimi yoksa macOS'un korumalıları).
    public private(set) var inaccessible = 0

    @ObservationIgnored private let root: String
    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let usedBytes: () -> Int64?
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var cancelFlag: CancelFlag?
    /// Önceki taramanın toplamı: ilerleme tahmini için.
    @ObservationIgnored private var lastTotal: Int64?
    @ObservationIgnored private let fullDiskAccess: () -> Bool
    /// Silme sürüyor: bu sırada bölüm kapansa da ağaç bırakılmaz (silinenler ağaçtan ve önbellekten düşsün).
    @ObservationIgnored private(set) var isDeleting = false

    public nonisolated static let defaultCacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("mystat/diskscan.cache")
    nonisolated static let tickInterval: Duration = .seconds(1)

    public init(root: String = NSHomeDirectory(), cacheURL: URL = DiskScanController.defaultCacheURL,
                now: @escaping () -> Date = { Date() }, usedBytes: @escaping () -> Int64? = { DiskScanController.volumeUsed() },
                fullDiskAccess: @escaping () -> Bool = { DiskAccess.hasFullDiskAccess() }) {
        self.root = root; self.cacheURL = cacheURL; self.now = now; self.usedBytes = usedBytes; self.fullDiskAccess = fullDiskAccess
        if let at = ScanCache.readDate(cacheURL) {
            phase = .ready(scannedAt: at)
            expireIfNeeded()
        } else {
            try? FileManager.default.removeItem(at: cacheURL)   // yoksa bir şey olmaz; bozuksa bırakılır
        }
    }

    static func emptyTree() -> DiskTree { DiskTree(root: DiskNode("~", 0), provider: nil) }
    private var treeLoaded: Bool { tree.scanIndex != nil }

    /// Taranan bayt / tahmin; bitene kadar en fazla 0,99.
    nonisolated static func progress(bytes: Int64, estimate: Int64) -> Double {
        estimate > 0 ? min(0.99, Double(bytes) / Double(estimate)) : 0
    }

    nonisolated static func shortPath(_ path: String, root: String) -> String {
        path.hasPrefix(root) ? "~" + path.dropFirst(root.count) : path
    }

    /// Birimde kullanılan alan; önceki tarama yokken ilerleme tahmini bunun %80'i.
    public nonisolated static func volumeUsed() -> Int64? {
        var s = statfs()
        guard statfs(NSHomeDirectory(), &s) == 0 else { return nil }
        return Int64(s.f_blocks - s.f_bfree) * Int64(s.f_bsize)
    }

    // MARK: Tarama

    public func start() {
        expireIfNeeded()
        guard scanTask == nil else { return }
        loadGeneration += 1; loadTask?.cancel(); loadTask = nil
        let previous = (phase: phase, tree: tree, inaccessible: inaccessible)
        // İzinsizken istem çıkarabilecek klasörler açılmaz (§10); okunamayan sayılır, not bunu söyler.
        let scanner = fullDiskAccess() ? DirectoryScanner(root: root)
            : DirectoryScanner(root: root, skip: { DiskAccess.promptsWithoutAccess($0) })
        let live = DiskTree.scanned(scanner.index)
        _ = live.node(at: [])
        let estimate = lastTotal ?? usedBytes().map { Int64(Double($0) * 0.8) } ?? 0
        tree = live; inaccessible = 0
        phase = .scanning(progress: 0, scannedGB: 0, currentPath: "~")
        let flag = CancelFlag(), box = ProgressBox(), cacheURL = cacheURL
        cancelFlag = flag
        scanTask = Task { [weak self] in
            let work = Task.detached(priority: .utility) {
                scanner.scan(onProgress: { p in box.value.withLock { $0 = p } }, isCancelled: { flag.isSet })
            }
            let ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.tickInterval)
                    guard !Task.isCancelled else { return }
                    self?.tick(box.value.withLock { $0 }, estimate: estimate)
                }
            }
            let index = await work.value
            ticker.cancel()
            guard let self else { return }
            guard !flag.isSet else { return self.finish(nil, previous: previous) }
            let at = self.now()
            _ = await Task.detached(priority: .utility) { ScanCache.write(index, scannedAt: at, to: cacheURL) }.value
            self.finish((index, at), previous: previous)
        }
    }

    public func cancel() { cancelFlag?.set() }

    private func tick(_ p: DirectoryScanner.Progress?, estimate: Int64) {
        guard let p, scanTask != nil, cancelFlag?.isSet == false else { return }
        tree.refresh()
        phase = .scanning(progress: Self.progress(bytes: p.bytes, estimate: estimate), scannedGB: Double(p.bytes) / 1e9,
                          currentPath: Self.shortPath(p.currentPath, root: root))
    }

    private func finish(_ result: (index: ScanIndex, at: Date)?, previous: (phase: ScanPhase, tree: DiskTree, inaccessible: Int)) {
        scanTask = nil; cancelFlag = nil
        guard let result else {   // iptal: önceki durum; önbellek o sırada yükleniyorduysa yeniden yüklenir
            phase = previous.phase; tree = previous.tree; inaccessible = previous.inaccessible
            loadIfNeeded()
            return
        }
        tree.refresh()
        inaccessible = result.index.inaccessible
        lastTotal = result.index.totals()[0]
        phase = .ready(scannedAt: result.at)
        if !visible { tree = Self.emptyTree() }
    }

    // MARK: Silme

    /// Sepetteki öğeleri siler ya da çöpe taşır (§6.4). En derindeki öğeden başlar. Korunan, ev dışı ya da taramadan
    /// sonra değişmiş öğeye dokunmaz. Silinenler ağaçtan ve dizinden düşer, önbellek yeniden yazılır.
    public func delete(_ items: [BasketItem], mode: DeleteMode) async -> DeleteOutcome {
        guard scanTask == nil, treeLoaded, case .ready(let scannedAt) = phase else {
            return DeleteOutcome(freedGB: 0, failed: items.map(\.name), changed: [])
        }
        isDeleting = true
        let base = URL(fileURLWithPath: root).standardizedFileURL
        var failed = Set<[String]>(), changed = Set<[String]>()
        var jobs: [(path: [String], url: URL, fileID: UInt64)] = []
        for item in items.sorted(by: { $0.path.count > $1.path.count }) {
            let url = base.appendingPathComponent(item.path.joined(separator: "/")).standardizedFileURL
            guard DeletionGuard.reason(path: item.path) == nil, let fid = item.fileID,
                  !item.path.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.contains("/") }),
                  url.path.hasPrefix(base.path + "/") else { failed.insert(item.path); continue }
            jobs.append((item.path, url, fid))
        }
        let t = tree, js = jobs, trash = mode == .trash
        let results = await Task.detached(priority: .userInitiated) {
            js.map { FileRemover.remove($0.url, expectedFileID: $0.fileID, toTrash: trash) }
        }.value
        var freed: Int64 = 0
        for (job, r) in zip(js, results) {
            switch r {
            case .removed(let b): freed += b; t.remove(at: job.path)
            case .changed: changed.insert(job.path)
            case .failed(_, let f): failed.insert(job.path); freed += f; t.shrink(at: job.path, by: Double(f) / 1e9)
            }
        }
        if t === tree, let index = t.scanIndex {   // bu arada yeni tarama başlamadıysa
            let url = cacheURL
            _ = await Task.detached(priority: .utility) { ScanCache.write(index, scannedAt: scannedAt, to: url) }.value
        }
        isDeleting = false
        if !visible, scanTask == nil { tree = Self.emptyTree() }   // silme sürerken bölüm kapandı
        return DeleteOutcome(freedGB: Double(freed) / 1e9, failed: items.filter { failed.contains($0.path) }.map(\.name),
                             changed: items.filter { changed.contains($0.path) }.map(\.name))
    }

    // MARK: Görünürlük ve önbellek

    /// Disk bölümü açıldı/kapandı. Kapalıyken ağaç bırakılır; açılınca geçerli önbellekten yüklenir.
    public func setVisible(_ v: Bool) {
        visible = v
        expireIfNeeded()
        guard scanTask == nil else { return }
        guard v else {
            loadGeneration += 1; loadTask?.cancel(); loadTask = nil
            if !isDeleting { tree = Self.emptyTree() }   // silme bitince bırakılır
            return
        }
        loadIfNeeded()
    }

    /// Bölüm açık, sonuç geçerli ama ağaç bellekte değilse önbellekten arka planda yüklenir.
    private func loadIfNeeded() {
        guard visible, scanTask == nil, case .ready = phase, !treeLoaded, loadTask == nil else { return }
        loadGeneration += 1
        let gen = loadGeneration, url = cacheURL
        loadTask = Task { [weak self] in
            let index = await Task.detached(priority: .userInitiated) { ScanCache.read(url) }.value
            guard let self, gen == self.loadGeneration else { return }
            self.loadTask = nil
            guard let index else {   // bozuk önbellek
                try? FileManager.default.removeItem(at: url)
                self.phase = .none
                return
            }
            let t = DiskTree.scanned(index)
            _ = t.node(at: [])
            self.tree = t
            self.inaccessible = index.inaccessible
            self.lastTotal = index.totals()[0]
        }
    }

    private func expireIfNeeded() {
        guard case .ready(let at) = phase, now().timeIntervalSince(at) >= ScanPhase.validity else { return }
        phase = .none; tree = Self.emptyTree(); inaccessible = 0
        try? FileManager.default.removeItem(at: cacheURL)
    }

    /// Testler için: süren tarama ve önbellek yüklemesi bitene kadar bekler.
    func waitUntilIdle() async {
        while let t = scanTask ?? loadTask { await t.value }
    }
}

private final class CancelFlag: Sendable {
    private let flag = Atomic<Bool>(false)
    var isSet: Bool { flag.load(ordering: .relaxed) }
    func set() { flag.store(true, ordering: .relaxed) }
}

private final class ProgressBox: Sendable {
    let value = Mutex<DirectoryScanner.Progress?>(nil)
}

/// Önbellek dosyası: "MYSC", sürüm, tarama zamanı, ardından LZFSE ile sıkıştırılmış `ScanIndex.encoded()`.
enum ScanCache {
    static let magic = Array("MYSC".utf8)
    static let version: UInt32 = 1
    static let headerSize = 16

    @discardableResult
    static func write(_ index: ScanIndex, scannedAt: Date, to url: URL) -> Bool {
        guard let payload = try? (index.encoded() as NSData).compressed(using: .lzfse) as Data else { return false }
        var d = Data(magic)
        withUnsafeBytes(of: version) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: scannedAt.timeIntervalSince1970) { d.append(contentsOf: $0) }
        d.append(payload)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? d.write(to: url, options: .atomic)) != nil
    }

    /// Yalnızca başlık: uygulama açılışında ağaç yüklenmeden geçerlilik bilinsin.
    static func readDate(_ url: URL) -> Date? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        guard let head = try? fh.read(upToCount: headerSize) else { return nil }
        return date(head)
    }

    static func read(_ url: URL) -> ScanIndex? {
        guard let d = try? Data(contentsOf: url), d.count > headerSize, date(d) != nil,
              let raw = try? (d.subdata(in: headerSize..<d.count) as NSData).decompressed(using: .lzfse) as Data else { return nil }
        return ScanIndex(decoding: raw)
    }

    private static func date(_ d: Data) -> Date? {
        guard d.count >= headerSize else { return nil }
        let b = Array(d.prefix(headerSize))
        guard Array(b[0..<4]) == magic else { return nil }
        let (v, t) = b.withUnsafeBytes { ($0.loadUnaligned(fromByteOffset: 4, as: UInt32.self), $0.loadUnaligned(fromByteOffset: 8, as: Double.self)) }
        guard v == version, t.isFinite else { return nil }
        return Date(timeIntervalSince1970: t)
    }
}
