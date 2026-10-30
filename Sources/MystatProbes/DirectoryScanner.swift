import Darwin
import Foundation
import MystatCore
import Synchronization

/// Scans the home folder with `getattrlistbulk`: one bulk read per folder, a few threads.
/// Symbolic links are not followed and other volumes are not crossed. A hardlink is counted once; dataless files (offloaded to iCloud) are
/// not counted at all. Size is the space allocated on disk (same as `du`). Unreadable folders are counted and the scan continues.
/// The result accumulates in `index`; it can be read while the scan runs. A scanner is run once.
public final class DirectoryScanner: Sendable {
    public struct Progress: Sendable, Equatable {
        public let bytes: Int64
        public let currentPath: String
        public let dirs: Int
    }

    public let index: ScanIndex
    private let root: String
    private let workers: Int
    /// Folders whose path (relative to the home root) is listed are not opened (those that could prompt for permission); they count as unreadable.
    private let skip: @Sendable (String) -> Bool
    static let bufferSize = 256 * 1024
    static let progressInterval: UInt64 = 250_000_000   // ns; ≈ 4 times/s

    private struct Work {
        var stack: [(id: Int32, path: String)]
        var busy = 0
        var bytes: Int64 = 0
        var dirs = 0
        var current = ""
        var lastReport: UInt64 = 0
    }
    private let work: Mutex<Work>
    private let linked = Mutex(Set<UInt64>())   // files with multiple links: the first one seen is counted

    public init(root: String, workers: Int = 4, skip: @escaping @Sendable (String) -> Bool = { _ in false }) {
        self.root = root
        self.workers = max(1, workers)
        self.skip = skip
        index = ScanIndex(rootName: "~")
        work = Mutex(Work(stack: [(0, root)]))
    }

    /// Blocking; call from a separate task. `onProgress` fires ≈ 4 times/s and once at the end. When `isCancelled` becomes true,
    /// the threads finish the folder they are on and return.
    public func scan(onProgress: @Sendable (Progress) -> Void, isCancelled: @Sendable () -> Bool) -> ScanIndex {
        var st = stat()
        guard stat(root, &st) == 0 else { index.noteInaccessible(); return index }
        let dev = st.st_dev
        DispatchQueue.concurrentPerform(iterations: workers) { _ in
            runWorker(dev: dev, onProgress: onProgress, isCancelled: isCancelled)
        }
        index.finishAdding()
        onProgress(work.withLock { Progress(bytes: $0.bytes, currentPath: $0.current, dirs: $0.dirs) })
        return index
    }

    private enum Next { case item(Int32, String), wait, done }

    private func runWorker(dev: dev_t, onProgress: @Sendable (Progress) -> Void, isCancelled: @Sendable () -> Bool) {
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Self.bufferSize, alignment: 8)
        defer { buf.deallocate() }
        while !isCancelled() {
            let next: Next = work.withLock { w in
                if let it = w.stack.popLast() { w.busy += 1; return .item(it.id, it.path) }
                return w.busy == 0 ? .done : .wait
            }
            guard case .item(let id, let path) = next else {
                if case .done = next { return }
                usleep(500)   // another thread has not yet added a subfolder
                continue
            }
            let rel = path.count > root.count ? String(path.dropFirst(root.count + 1)) : ""
            let listing = skip(rel) ? nil : list(path, dev: dev, buf: buf)
            var children: [(id: Int32, path: String)] = []
            if let l = listing {
                for d in l.subdirs { children.append((index.addDirectory(parent: id, name: d.name, fileID: d.fileID), path + "/" + d.name)) }
                index.addFiles(dir: id, big: l.big, smallBytes: l.smallBytes, smallCount: l.smallCount, cloudCount: l.cloud)
            } else {
                index.noteInaccessible()
            }
            let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let report: Progress? = work.withLock { w in
                w.stack.append(contentsOf: children); w.busy -= 1
                w.bytes += listing?.bytes ?? 0; w.dirs += 1; w.current = path
                guard now &- w.lastReport >= Self.progressInterval else { return nil }
                w.lastReport = now
                return Progress(bytes: w.bytes, currentPath: path, dirs: w.dirs)
            }
            if let report { onProgress(report) }
        }
    }

    struct Listing {
        var subdirs: [(name: String, fileID: UInt64)] = []
        var big: [(name: String, bytes: Int64, fileID: UInt64)] = []
        var smallBytes: Int64 = 0, smallCount = 0
        var bytes: Int64 = 0
        /// Only files and folders that live in the cloud (offloaded to iCloud): they take no space, and deleting them removes them from the cloud too.
        var cloud = 0
    }

    /// A folder's direct entries; nil if it cannot be opened. If a read fails midway, what was read so far is returned.
    private func list(_ path: String, dev: dev_t, buf: UnsafeMutableRawPointer) -> Listing? {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var al = attrlist()
        al.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        al.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME | ATTR_CMN_DEVID | ATTR_CMN_OBJTYPE | ATTR_CMN_FLAGS | ATTR_CMN_FILEID)
        al.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE)
        var out = Listing()
        while true {
            let n = getattrlistbulk(fd, &al, buf, Self.bufferSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
            if n <= 0 { break }
            var p = buf
            for _ in 0..<n {
                // Order is the kernel's fixed layout: length, returned attributes, name, device, type, flags, id,
                // link count, allocated size. FSOPT_PACK_INVAL_ATTRS fills invalid ones with zero.
                let len = Int(p.loadUnaligned(as: UInt32.self))
                var q = p + 4 + MemoryLayout<attribute_set_t>.size
                let nameRef = q.loadUnaligned(as: attrreference_t.self)
                let name = String(cString: (q + Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                q += MemoryLayout<attrreference_t>.size
                let entryDev = q.loadUnaligned(as: dev_t.self); q += 4
                let type = q.loadUnaligned(as: UInt32.self); q += 4
                let flags = q.loadUnaligned(as: UInt32.self); q += 4
                let fileID = q.loadUnaligned(as: UInt64.self); q += 8
                let links = q.loadUnaligned(as: UInt32.self); q += 4
                let alloc = q.loadUnaligned(as: Int64.self)
                p += len

                let dataless = flags & UInt32(SF_DATALESS) != 0
                if type == UInt32(VDIR.rawValue) {
                    if dataless { out.cloud += 1 }   // opening it may make the content download from the cloud
                    else if entryDev == dev { out.subdirs.append((name, fileID)) }
                } else if type == UInt32(VREG.rawValue), dataless {
                    out.cloud += 1
                } else if type == UInt32(VREG.rawValue) {
                    if links > 1, !linked.withLock({ $0.insert(fileID).inserted }) { continue }
                    out.bytes += alloc
                    if alloc >= ScanIndex.smallFile { out.big.append((name, alloc, fileID)) }
                    else { out.smallBytes += alloc; out.smallCount += 1 }
                }
            }
        }
        return out
    }
}
