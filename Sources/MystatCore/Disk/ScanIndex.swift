import Foundation
import Synchronization

/// Bir klasörün haritadaki çocuğu: alt klasör, 10 MB üstü dosya ya da küçük dosyaların toplamı ("Diğer").
public struct ScanChild: Sendable, Equatable {
    public enum Ref: Sendable, Equatable { case dir(Int32), file(fileID: UInt64), other(count: Int) }
    public let name: String
    public let bytes: Int64
    public let ref: Ref
    /// Alt ağaçta yalnızca bulutta duran (iCloud'a boşaltılmış) öğe sayısı; boyuta katılmaz.
    public let cloud: Int

    public init(name: String, bytes: Int64, ref: Ref, cloud: Int = 0) { self.name = name; self.bytes = bytes; self.ref = ref; self.cloud = cloud }
}

/// Alt ağaç toplamları ve çocuk listeleri (CSR), dizinin bir anındaki tutarlı görüntüsü.
public struct ScanTotals: Sendable {
    let bytes: [Int64]
    let cloudItems: [Int32]                       // alt ağaçtaki yalnızca bulutta duran öğeler
    let childStart: [Int32], childDirs: [Int32]   // klasör → alt klasörler
    let fileStart: [Int32], files: [Int32]        // klasör → büyük dosyalar

    public var dirCount: Int { bytes.count }
    public subscript(dir: Int32) -> Int64 { Int(dir) < bytes.count ? bytes[Int(dir)] : 0 }
    public func cloud(_ dir: Int32) -> Int { Int(dir) < cloudItems.count ? Int(cloudItems[Int(dir)]) : 0 }
}

/// Ev klasörü taramasının sıkı dizini (spec §6.4 "Hafıza tasarrufu"). 600 bin klasör düğüm nesnesiyle ≈ 100 MB
/// tutardı; burada klasör başına ≈ 30 bayt ve tek bir ad tamponu. Klasörler ve 10 MB üstü dosyalar ayrı, küçük
/// dosyalar klasör başına toplam. Tarayıcının iş parçacıkları yazarken arayüz okuyabilsin diye iç kilitli bir sınıf;
/// kopyalanmaz, tarama sürerken de aynı nesne okunur.
public final class ScanIndex: Sendable {
    public static let smallFile: Int64 = 10_000_000
    public static let otherName = "Diğer"
    static let magic: [UInt8] = Array("MYSI".utf8)
    static let formatVersion: UInt32 = 2   // 2: bulut sayısı sütunu
    /// Önbellekte kabul edilen en büyük toplam (1 EB): bozuk ama yapısı geçerli veri toplarken taşmasın.
    static let maxTotalBytes: Int64 = 1_000_000_000_000_000_000

    struct Storage {
        // Klasörler; numara = dizi sırası, kök 0. Üst klasör her zaman çocuğundan önce eklenir (parent < id).
        var parent: [Int32] = []          // kök -1, silinmiş -2
        var nameStart: [UInt32] = []
        var nameLen: [UInt16] = []
        var ownSmall: [Int64] = []
        var smallCount: [Int32] = []
        var cloud: [Int32] = []           // doğrudan içindeki yalnızca bulutta duran öğeler
        var fileID: [UInt64] = []
        // Büyük dosyalar.
        var fDir: [Int32] = []            // silinmiş -1
        var fNameStart: [UInt32] = []
        var fNameLen: [UInt16] = []
        var fBytes: [Int64] = []
        var fID: [UInt64] = []
        var names: [UInt8] = []
        var inaccessible = 0
        var version = 0
        var cache: (version: Int, totals: ScanTotals)?

        mutating func appendName(_ s: String) -> (UInt32, UInt16) {
            let start = UInt32(names.count)
            names.append(contentsOf: s.utf8)
            return (start, UInt16(names.count - Int(start)))
        }
        func name(_ start: UInt32, _ len: UInt16) -> String {
            String(decoding: names[Int(start)..<Int(start) + Int(len)], as: UTF8.self)
        }
    }

    private let state: Mutex<Storage>

    public init(rootName: String) {
        var s = Storage()
        let (start, len) = s.appendName(rootName)
        s.parent = [-1]; s.nameStart = [start]; s.nameLen = [len]; s.ownSmall = [0]; s.smallCount = [0]; s.cloud = [0]; s.fileID = [0]
        state = Mutex(s)
    }

    private init(storage: Storage) { state = Mutex(storage) }

    public var rootName: String { state.withLock { $0.name($0.nameStart[0], $0.nameLen[0]) } }
    public var dirCount: Int { state.withLock { $0.parent.count } }
    public var inaccessible: Int { state.withLock { $0.inaccessible } }
    public func noteInaccessible() { state.withLock { $0.inaccessible += 1 } }

    /// Klasör ekle; dönen numara çocuklarını eklerken kullanılır. Kök 0.
    @discardableResult
    public func addDirectory(parent: Int32, name: String, fileID: UInt64) -> Int32 {
        state.withLock { s in
            precondition(parent >= 0 && Int(parent) < s.parent.count, "üst klasör önce eklenir")
            let (start, len) = s.appendName(name)
            s.parent.append(parent); s.nameStart.append(start); s.nameLen.append(len)
            s.ownSmall.append(0); s.smallCount.append(0); s.cloud.append(0); s.fileID.append(fileID)
            s.version += 1
            return Int32(s.parent.count - 1)
        }
    }

    /// Bir klasörün doğrudan dosyaları: büyükler ayrı, küçüklerin toplamı ve sayısı; yalnızca bulutta duranların sayısı.
    public func addFiles(dir: Int32, big: [(name: String, bytes: Int64, fileID: UInt64)], smallBytes: Int64, smallCount: Int, cloudCount: Int = 0) {
        state.withLock { s in
            let d = Int(dir)
            s.ownSmall[d] += smallBytes; s.smallCount[d] += Int32(smallCount); s.cloud[d] += Int32(cloudCount)
            for f in big {
                let (start, len) = s.appendName(f.name)
                s.fDir.append(dir); s.fNameStart.append(start); s.fNameLen.append(len); s.fBytes.append(f.bytes); s.fID.append(f.fileID)
            }
            s.version += 1
        }
    }

    public func fileID(ofDir dir: Int32) -> UInt64 { state.withLock { $0.fileID[Int(dir)] } }

    /// Silinen klasör: alt ağacıyla birlikte toplamlardan ve listelerden düşer.
    public func removeDirectory(_ dir: Int32) {
        state.withLock { s in
            guard dir > 0, Int(dir) < s.parent.count else { return }
            s.parent[Int(dir)] = -2; s.version += 1
        }
    }

    public func removeFile(dir: Int32, fileID: UInt64) {
        state.withLock { s in
            guard let j = s.fDir.indices.first(where: { s.fDir[$0] == dir && s.fID[$0] == fileID }) else { return }
            s.fDir[j] = -1; s.version += 1
        }
    }

    /// Tarama bitince dizileri tam boylarına indirir (büyürken iki katına çıkan kapasite geri verilir).
    public func finishAdding() {
        state.withLock { s in
            func fit<T>(_ a: inout [T]) { a = Array(unsafeUninitializedCapacity: a.count) { buf, n in
                n = buf.initialize(fromContentsOf: a) } }
            fit(&s.parent); fit(&s.nameStart); fit(&s.nameLen); fit(&s.ownSmall); fit(&s.smallCount); fit(&s.cloud); fit(&s.fileID)
            fit(&s.fDir); fit(&s.fNameStart); fit(&s.fNameLen); fit(&s.fBytes); fit(&s.fID); fit(&s.names)
        }
    }

    /// Alt ağaç toplamları ve çocuk listeleri; dizin değişmediyse önceki görüntü döner. O(n).
    public func totals() -> ScanTotals {
        state.withLock { s in
            if let c = s.cache, c.version == s.version { return c.totals }
            let t = Self.computeTotals(s)
            s.cache = (s.version, t)
            return t
        }
    }

    private static func computeTotals(_ s: Storage) -> ScanTotals {
        let n = s.parent.count
        var bytes = s.ownSmall, cloud = s.cloud
        var childCount = [Int32](repeating: 0, count: n + 1), fileCount = [Int32](repeating: 0, count: n + 1)
        for j in s.fDir.indices where s.fDir[j] >= 0 {
            bytes[Int(s.fDir[j])] += s.fBytes[j]; fileCount[Int(s.fDir[j]) + 1] += 1
        }
        for i in stride(from: n - 1, to: 0, by: -1) where s.parent[i] >= 0 {
            bytes[Int(s.parent[i])] += bytes[i]; cloud[Int(s.parent[i])] += cloud[i]; childCount[Int(s.parent[i]) + 1] += 1
        }
        for i in 0..<n { childCount[i + 1] += childCount[i]; fileCount[i + 1] += fileCount[i] }
        var childDirs = [Int32](repeating: 0, count: Int(childCount[n])), files = [Int32](repeating: 0, count: Int(fileCount[n]))
        var cNext = childCount, fNext = fileCount
        for i in 1..<max(n, 1) where s.parent[i] >= 0 {
            let p = Int(s.parent[i]); childDirs[Int(cNext[p])] = Int32(i); cNext[p] += 1
        }
        for j in s.fDir.indices where s.fDir[j] >= 0 {
            let d = Int(s.fDir[j]); files[Int(fNext[d])] = Int32(j); fNext[d] += 1
        }
        return ScanTotals(bytes: bytes, cloudItems: cloud, childStart: childCount, childDirs: childDirs, fileStart: fileCount, files: files)
    }

    /// Bir klasörün çocukları: tüm alt klasörler ve büyük dosyalar (büyükten küçüğe), sonda küçük dosyaların "Diğer"i.
    /// Boş (0 bayt) klasörler listelenmez.
    public func children(of dir: Int32, totals t: ScanTotals) -> [ScanChild] {
        let d = Int(dir)
        guard d >= 0, d < t.dirCount else { return [] }
        return state.withLock { s in
            var out: [ScanChild] = []
            for k in Int(t.childStart[d])..<Int(t.childStart[d + 1]) {
                let c = t.childDirs[k], b = t.bytes[Int(c)]
                if b > 0 { out.append(ScanChild(name: s.name(s.nameStart[Int(c)], s.nameLen[Int(c)]), bytes: b, ref: .dir(c), cloud: Int(t.cloudItems[Int(c)]))) }
            }
            for k in Int(t.fileStart[d])..<Int(t.fileStart[d + 1]) {
                let j = Int(t.files[k])
                guard s.fDir[j] >= 0 else { continue }
                out.append(ScanChild(name: s.name(s.fNameStart[j], s.fNameLen[j]), bytes: s.fBytes[j], ref: .file(fileID: s.fID[j])))
            }
            out.sort { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }
            if s.ownSmall[d] > 0 {
                out.append(ScanChild(name: Self.otherName, bytes: s.ownSmall[d], ref: .other(count: Int(s.smallCount[d]))))
            }
            return out
        }
    }

    public func path(of dir: Int32) -> [String] {
        state.withLock { s in
            var out: [String] = [], i = Int(dir)
            while i > 0 { out.append(s.name(s.nameStart[i], s.nameLen[i])); i = Int(s.parent[i]) }
            return out.reversed()
        }
    }

    /// Dizilerin kullandığı bellek. Kapasite değil: `malloc` büyük blokları yuvarlar (600 bin elemana ≈ 786 bin), yazılmayan
    /// kuyruk yerleşik belleğe girmez ve yuvarlama süreçteki ayırma durumuna göre değişir. Gerçek ayak izi tools/disk-check.sh'de.
    var storageBytes: Int {
        state.withLock { s in
            func b<T>(_ a: [T]) -> Int { a.count * MemoryLayout<T>.stride }
            return b(s.parent) + b(s.nameStart) + b(s.nameLen) + b(s.ownSmall) + b(s.smallCount) + b(s.cloud) + b(s.fileID)
                + b(s.fDir) + b(s.fNameStart) + b(s.fNameLen) + b(s.fBytes) + b(s.fID) + b(s.names)
        }
    }

    // MARK: Önbellek biçimi

    /// "MYSI", sürüm, sayılar, ardından diziler ham olarak (küçük uçlu). Sıkıştırmayı çağıran yapar.
    public func encoded() -> Data {
        state.withLock { s in
            var d = Data(Self.magic)
            func put<T: BitwiseCopyable>(_ v: T) { withUnsafeBytes(of: v) { d.append(contentsOf: $0) } }
            func put<T: BitwiseCopyable>(_ a: [T]) { a.withUnsafeBytes { d.append(contentsOf: $0) } }
            put(Self.formatVersion)
            put(UInt32(s.parent.count)); put(UInt32(s.fDir.count)); put(UInt32(s.names.count)); put(UInt32(s.inaccessible))
            put(s.parent); put(s.nameStart); put(s.nameLen); put(s.ownSmall); put(s.smallCount); put(s.cloud); put(s.fileID)
            put(s.fDir); put(s.fNameStart); put(s.fNameLen); put(s.fBytes); put(s.fID); put(s.names)
            return d
        }
    }

    /// Bozuk, eksik ya da başka sürüm veri → nil.
    public convenience init?(decoding data: Data) {
        guard let s = Self.decode(data) else { return nil }
        self.init(storage: s)
    }

    private static func decode(_ data: Data) -> Storage? {
        var r = Reader(data: data)
        guard r.bytes(4) == magic, r.value(UInt32.self) == formatVersion,
              let n = r.value(UInt32.self).map(Int.init), let f = r.value(UInt32.self).map(Int.init),
              let nb = r.value(UInt32.self).map(Int.init), let inacc = r.value(UInt32.self), n >= 1 else { return nil }
        var s = Storage()
        guard let parent = r.array(Int32.self, n), let nameStart = r.array(UInt32.self, n), let nameLen = r.array(UInt16.self, n),
              let ownSmall = r.array(Int64.self, n), let smallCount = r.array(Int32.self, n), let cloud = r.array(Int32.self, n),
              let fileID = r.array(UInt64.self, n),
              let fDir = r.array(Int32.self, f), let fNameStart = r.array(UInt32.self, f), let fNameLen = r.array(UInt16.self, f),
              let fBytes = r.array(Int64.self, f), let fID = r.array(UInt64.self, f), let names = r.array(UInt8.self, nb),
              r.atEnd else { return nil }
        // Yapı denetimi: üst klasör önce, adlar tamponun içinde, boyutlar eksi değil.
        guard parent[0] == -1 else { return nil }
        for i in 1..<n where !(parent[i] == -2 || (parent[i] >= 0 && Int(parent[i]) < i)) { return nil }
        for i in 0..<n where Int(nameStart[i]) + Int(nameLen[i]) > nb || ownSmall[i] < 0 || smallCount[i] < 0 || cloud[i] < 0 { return nil }
        for j in 0..<f where !(fDir[j] >= -1 && Int(fDir[j]) < n) || Int(fNameStart[j]) + Int(fNameLen[j]) > nb || fBytes[j] < 0 {
            return nil
        }
        // Toplamlar alt ağaç toplamlarının üst sınırı: burada taşmıyorsa `computeTotals` da taşmaz.
        var total: Int64 = 0, cloudTotal: Int32 = 0
        for v in ownSmall + fBytes {
            let (sum, over) = total.addingReportingOverflow(v)
            guard !over, sum <= maxTotalBytes else { return nil }
            total = sum
        }
        for v in cloud {
            let (sum, over) = cloudTotal.addingReportingOverflow(v)
            guard !over else { return nil }
            cloudTotal = sum
        }
        s.parent = parent; s.nameStart = nameStart; s.nameLen = nameLen; s.ownSmall = ownSmall; s.smallCount = smallCount; s.cloud = cloud
        s.fileID = fileID; s.fDir = fDir; s.fNameStart = fNameStart; s.fNameLen = fNameLen; s.fBytes = fBytes; s.fID = fID
        s.names = names; s.inaccessible = Int(inacc)
        return s
    }

    private struct Reader {
        let data: Data
        var pos = 0
        var atEnd: Bool { pos == data.count }

        mutating func bytes(_ n: Int) -> [UInt8]? {
            guard n >= 0, data.count - pos >= n else { return nil }
            defer { pos += n }
            let base = data.startIndex + pos
            return Array(data[base..<base + n])
        }
        mutating func value<T: BitwiseCopyable>(_: T.Type) -> T? {
            guard let b = bytes(MemoryLayout<T>.size) else { return nil }
            return b.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
        }
        mutating func array<T: BitwiseCopyable>(_: T.Type, _ count: Int) -> [T]? {
            let size = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
            guard !size.overflow, size.partialValue <= data.count - pos else { return nil }
            let base = data.startIndex + pos
            pos += size.partialValue
            return [T](unsafeUninitializedCapacity: count) { buf, n in
                data[base..<base + size.partialValue].withUnsafeBytes { src in
                    UnsafeMutableRawBufferPointer(buf).copyMemory(from: src)
                }
                n = count
            }
        }
    }
}
