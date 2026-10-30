import Foundation
import Synchronization

/// A folder's child on the map: a subfolder, a file over 10 MB, or the total of small files ("Other").
public struct ScanChild: Sendable, Equatable {
    public enum Ref: Sendable, Equatable { case dir(Int32), file(fileID: UInt64), other(count: Int) }
    public let name: String
    public let bytes: Int64
    public let ref: Ref
    /// Number of cloud-only items in the subtree (offloaded to iCloud); not included in the size.
    public let cloud: Int

    public init(name: String, bytes: Int64, ref: Ref, cloud: Int = 0) { self.name = name; self.bytes = bytes; self.ref = ref; self.cloud = cloud }
}

/// Subtree totals and child lists (CSR): a consistent snapshot of the index at one moment.
public struct ScanTotals: Sendable {
    let bytes: [Int64]
    let cloudItems: [Int32]                       // cloud-only items in the subtree
    let childStart: [Int32], childDirs: [Int32]   // folder → subfolders
    let fileStart: [Int32], files: [Int32]        // folder → large files

    public var dirCount: Int { bytes.count }
    public subscript(dir: Int32) -> Int64 { Int(dir) < bytes.count ? bytes[Int(dir)] : 0 }
    public func cloud(_ dir: Int32) -> Int { Int(dir) < cloudItems.count ? Int(cloudItems[Int(dir)]) : 0 }
}

/// Compact index of the home folder scan, designed to save memory. 600 thousand folders as node objects would take ≈ 100 MB;
/// here it is ≈ 30 bytes per folder and a single name buffer. Folders and files over 10 MB are stored separately, small
/// files as one total per folder. A class with an internal lock so the UI can read while the scanner's threads write;
/// it is not copied, and the same object is read while the scan runs.
public final class ScanIndex: Sendable {
    public static let smallFile: Int64 = 10_000_000
    public static let otherName = "Diğer"
    static let magic: [UInt8] = Array("MYSI".utf8)
    static let formatVersion: UInt32 = 2   // 2: cloud count column
    /// Largest total accepted from the cache (1 EB): so corrupt but structurally valid data does not overflow when summed.
    static let maxTotalBytes: Int64 = 1_000_000_000_000_000_000

    struct Storage {
        // Folders; id = array order, root is 0. A parent is always added before its child (parent < id).
        var parent: [Int32] = []          // root -1, deleted -2
        var nameStart: [UInt32] = []
        var nameLen: [UInt16] = []
        var ownSmall: [Int64] = []
        var smallCount: [Int32] = []
        var cloud: [Int32] = []           // cloud-only items directly inside
        var fileID: [UInt64] = []
        // Large files.
        var fDir: [Int32] = []            // deleted -1
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

    /// Adds a folder; the returned id is used when adding its children. Root is 0.
    @discardableResult
    public func addDirectory(parent: Int32, name: String, fileID: UInt64) -> Int32 {
        state.withLock { s in
            precondition(parent >= 0 && Int(parent) < s.parent.count, "parent directory must be added first")
            let (start, len) = s.appendName(name)
            s.parent.append(parent); s.nameStart.append(start); s.nameLen.append(len)
            s.ownSmall.append(0); s.smallCount.append(0); s.cloud.append(0); s.fileID.append(fileID)
            s.version += 1
            return Int32(s.parent.count - 1)
        }
    }

    /// A folder's direct files: large ones separately, the total and count of small ones; the count of cloud-only ones.
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

    /// A deleted folder: removed with its subtree from the totals and lists.
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

    /// When the scan finishes, shrinks the arrays to their exact size (capacity that doubled while growing is returned).
    public func finishAdding() {
        state.withLock { s in
            func fit<T>(_ a: inout [T]) { a = Array(unsafeUninitializedCapacity: a.count) { buf, n in
                n = buf.initialize(fromContentsOf: a) } }
            fit(&s.parent); fit(&s.nameStart); fit(&s.nameLen); fit(&s.ownSmall); fit(&s.smallCount); fit(&s.cloud); fit(&s.fileID)
            fit(&s.fDir); fit(&s.fNameStart); fit(&s.fNameLen); fit(&s.fBytes); fit(&s.fID); fit(&s.names)
        }
    }

    /// Subtree totals and child lists; if the index has not changed, the previous snapshot is returned. O(n).
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

    /// A folder's children: all subfolders and large files (largest first), with the "Other" of small files at the end.
    /// Empty (0 byte) folders are not listed.
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

    /// Memory used by the arrays. Not capacity: `malloc` rounds up large blocks (600 thousand elements ≈ 786 thousand), the unwritten
    /// tail does not count toward resident memory, and rounding varies with the process's allocation state. The real footprint is checked by tools/disk-check.sh.
    var storageBytes: Int {
        state.withLock { s in
            func b<T>(_ a: [T]) -> Int { a.count * MemoryLayout<T>.stride }
            return b(s.parent) + b(s.nameStart) + b(s.nameLen) + b(s.ownSmall) + b(s.smallCount) + b(s.cloud) + b(s.fileID)
                + b(s.fDir) + b(s.fNameStart) + b(s.fNameLen) + b(s.fBytes) + b(s.fID) + b(s.names)
        }
    }

    // MARK: Cache format

    /// "MYSI", version, counts, then the arrays raw (little-endian). The caller does the compression.
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

    /// Corrupt, incomplete or other-version data → nil.
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
        // Structure check: parent first, names inside the buffer, sizes non-negative.
        guard parent[0] == -1 else { return nil }
        for i in 1..<n where !(parent[i] == -2 || (parent[i] >= 0 && Int(parent[i]) < i)) { return nil }
        for i in 0..<n where Int(nameStart[i]) + Int(nameLen[i]) > nb || ownSmall[i] < 0 || smallCount[i] < 0 || cloud[i] < 0 { return nil }
        for j in 0..<f where !(fDir[j] >= -1 && Int(fDir[j]) < n) || Int(fNameStart[j]) + Int(fNameLen[j]) > nb || fBytes[j] < 0 {
            return nil
        }
        // Totals are an upper bound on the subtree totals: if they do not overflow here, `computeTotals` will not either.
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
