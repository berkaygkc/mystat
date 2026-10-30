import Foundation

public enum NodeKind: Sendable, Equatable { case folder, regen, docker, file, other }

/// A node of the disk tree. Size in GB.
public final class DiskNode {
    public let name: String
    public var size: Double
    public let isFile: Bool
    public let isDocker: Bool
    public var children: [DiskNode]?
    /// Its counterpart in the index for a scan tree; nil in sample data.
    public var ref: ScanChild.Ref?
    /// Filesystem identity (inode); used to verify the item has not changed before deletion. nil in sample data.
    public let fileID: UInt64?
    /// Number of items in the subtree that exist only in the cloud (offloaded to iCloud); the user is warned before deletion.
    public var cloudItems = 0

    /// Names of synthetic nodes in the scan tree: NUL cannot occur in a file name, so they never collide with a real "Other" folder.
    /// The screen shows "Other" (`displayName`).
    public static let smallFilesName = "\u{0}küçük"
    public static let restName = "\u{0}kalan"
    public static func display(_ name: String) -> String { name.first == "\u{0}" ? L10n.t("disk.other") : name }
    public var displayName: String { Self.display(name) }

    public init(_ name: String, _ size: Double, file: Bool = false, docker: Bool = false, _ children: [DiskNode]? = nil,
                ref: ScanChild.Ref? = nil, fileID: UInt64? = nil) {
        self.name = name; self.size = size; self.isFile = file; self.isDocker = docker; self.children = children
        self.ref = ref; self.fileID = fileID
    }

    /// Kind = color. In a scan tree `ref`, not the name "Other", decides: a real folder named
    /// "Other" on disk is a folder.
    public var kind: NodeKind {
        if case .other? = ref { return .other }
        if isDocker || name == "Docker" { return .docker }
        if ref == nil, name == L10n.t("disk.other") { return .other }   // sample data
        if Self.isRegen(name) { return .regen }
        if isFile { return .file }
        return .folder
    }

    /// Whether it can be entered. In sample data: whether child nodes can be generated; in a scan tree: whether it is a folder.
    public var canHaveChildren: Bool {
        if let ref { if case .dir = ref { return true } else { return false } }
        return !isFile && name != L10n.t("disk.other") && size >= 0.03
    }

    /// Names of regenerable folders. `Regex` is not Sendable; to be safe to read from the background scan too,
    /// a plain set and prefix check are used.
    static let regenNames: Set<String> = ["node_modules", ".next", "Caches", "DerivedData", "pnpm", "Homebrew", ".npm", ".cache"]
    static func isRegen(_ name: String) -> Bool { regenNames.contains { name.hasPrefix($0) } }
}

/// Produces a node's children on first open: `SampleGenerator` for sample data, `ScanIndex` for the scan tree.
public protocol DiskChildProvider: AnyObject {
    /// The node's children; nil if none.
    func children(of node: DiskNode, path: [String]) -> [DiskNode]?
}

/// Sample data.
public final class SampleProvider: DiskChildProvider {
    public init() {}
    public func children(of node: DiskNode, path: [String]) -> [DiskNode]? {
        SampleGenerator.generate(node, path: path)
        return node.children
    }
}

/// Produces nodes from the scan index. The index can keep growing while a scan runs; `totals` is a snapshot of the last `refresh`.
final class ScanProvider: DiskChildProvider {
    let index: ScanIndex
    var totals: ScanTotals
    /// Docker's data lives under these folders (color and deletion warning).
    static let dockerRoots: [[String]] = [["Library", "Containers", "com.docker.docker"], ["Library", "Group Containers", "group.com.docker"]]

    init(index: ScanIndex) { self.index = index; totals = index.totals() }

    func children(of node: DiskNode, path: [String]) -> [DiskNode]? {
        guard case .dir(let id)? = node.ref else { return nil }
        return index.children(of: id, totals: totals).map { make($0, path: path + [$0.name]) }
    }

    func make(_ c: ScanChild, path: [String]) -> DiskNode {
        let docker = Self.dockerRoots.contains { path.count >= $0.count && Array(path.prefix($0.count)) == $0 }
        let gb = Double(c.bytes) / 1e9
        switch c.ref {
        case .dir(let id):
            let n = DiskNode(c.name, gb, docker: docker, ref: c.ref, fileID: index.fileID(ofDir: id))
            n.cloudItems = c.cloud
            return n
        case .file(let fid): return DiskNode(c.name, gb, file: true, docker: docker, ref: c.ref, fileID: fid)
        case .other: return DiskNode(DiskNode.smallFilesName, gb, docker: docker, ref: c.ref)
        }
    }
}

public final class DiskTree {
    public let root: DiskNode
    private let provider: DiskChildProvider?

    public init(root: DiskNode, provider: DiskChildProvider? = SampleProvider()) { self.root = root; self.provider = provider }

    /// Scan result: nodes are produced from the index as they are visited.
    public static func scanned(_ index: ScanIndex) -> DiskTree {
        let p = ScanProvider(index: index)
        let root = DiskNode(index.rootName, Double(p.totals[0]) / 1e9, ref: .dir(0), fileID: index.fileID(ofDir: 0))
        root.cloudItems = p.totals.cloud(0)
        return DiskTree(root: root, provider: p)
    }

    /// The scan tree's index; nil in sample data.
    public var scanIndex: ScanIndex? { (provider as? ScanProvider)?.index }

    /// Finds the node by lazily generating child nodes along the path.
    public func node(at path: [String]) -> DiskNode? {
        var n = root
        expand(n, path: [])
        for (i, name) in path.enumerated() {
            guard let next = n.children?.first(where: { $0.name == name }) else { return nil }
            n = next
            expand(n, path: Array(path[...i]))
        }
        return n
    }

    private func expand(_ n: DiskNode, path: [String]) {
        guard n.children == nil, n.canHaveChildren, let provider else { return }
        n.children = provider.children(of: n, path: path)
    }

    /// While a scan runs, reflects new totals in the index into expanded nodes. Existing node objects are kept
    /// (bubble identity and animation continue); new children are added.
    public func refresh() {
        guard let p = provider as? ScanProvider else { return }
        p.totals = p.index.totals()
        root.size = Double(p.totals[0]) / 1e9; root.cloudItems = p.totals.cloud(0)
        update(root, path: [], p)
    }

    private func update(_ n: DiskNode, path: [String], _ p: ScanProvider) {
        guard let kids = n.children, case .dir(let id)? = n.ref else { return }
        func key(_ c: ScanChild) -> String { if case .other = c.ref { DiskNode.smallFilesName } else { c.name } }
        let old = Dictionary(kids.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        n.children = p.index.children(of: id, totals: p.totals).map { c in
            guard let o = old[key(c)] else { return p.make(c, path: path + [key(c)]) }
            o.size = Double(c.bytes) / 1e9; o.ref = c.ref; o.cloudItems = c.cloud
            update(o, path: path + [c.name], p)
            return o
        }
    }

    /// Interrupted deletion: the node's and its ancestors' sizes drop by the freed amount (inner detail stays stale until a rescan).
    public func shrink(at path: [String], by gb: Double) {
        guard gb > 0, node(at: path) != nil else { return }
        var n = root
        n.size -= gb
        for name in path {
            n = n.children!.first { $0.name == name }!
            n.size -= gb
        }
    }

    /// Removes the node from the tree and reduces its ancestors' sizes; returns the removed size. In a scan tree it is also removed
    /// from the index (to keep the cache current).
    @discardableResult
    public func remove(at path: [String]) -> Double {
        guard let last = path.last, let parent = node(at: Array(path.dropLast())),
              let i = parent.children?.firstIndex(where: { $0.name == last }) else { return 0 }
        let removed = parent.children![i]
        let size = removed.size
        parent.children!.remove(at: i)
        var n = root
        n.size -= size
        for name in path.dropLast() {
            n = n.children!.first { $0.name == name }!
            n.size -= size
        }
        if let p = provider as? ScanProvider {
            switch removed.ref {
            case .dir(let id)?: p.index.removeDirectory(id)
            case .file(let fid)?: if case .dir(let pid)? = parent.ref { p.index.removeFile(dir: pid, fileID: fid) }
            default: break
            }
            p.totals = p.index.totals()
        }
        return size
    }
}

/// Deterministic child node generation tied to the path, for unlimited depth in sample data.
enum SampleGenerator {
    static let pools: [String: [String]] = [
        "nm": ["next", "@next", "typescript", "@swc", "esbuild", "react-dom", "@prisma", "turbo", "sharp", "lightningcss", "@img", "playwright-core", "@babel", "webpack", "caniuse-lite", "date-fns", "lodash", "@tanstack", "rxjs", "zod"],
        "pkg": ["dist", "lib", "cjs", "esm", "node_modules", "bin", "src", "types", "vendor"],
        "next": ["cache", "server", "static", "standalone", "types", "webpack", "swc"],
        "cache": ["com.apple.{h}", "v3", "blobs", "index", "tmp", "store-{h}", "metadata", "objects"],
        "gen": ["src", "assets", "build", "dist", "logs", "data", "backup", "archive", "cache", ".git", "exports", "vendor", "public", "tests", "scripts", "models", "fixtures", "raw", "temp"],
        "files": ["export.zip", "dump.sql", "video.mp4", "dataset.parquet", "backup.tar.gz", "model.bin", "image.dmg", "recording.mov", "events.log", "archive.7z", "bundle.js.map", "snapshot.db"],
    ]

    static func generate(_ n: DiskNode, path: [String]) {
        guard n.children == nil, n.canHaveChildren else { return }
        // Seed: rng(Math.floor(hash01(path + '#') * 1e9) + 11), hash01 = (fnv % 1000) / 1000.
        let h01 = Double(fnv1a(path.joined(separator: "/") + "#") % 1000) / 1000
        var r = Mulberry32(seed: UInt32((h01 * 1e9).rounded(.down)) + 11)
        let nm = n.name
        var pool = "gen", fileP = 0.28
        if nm.hasPrefix("node_modules") { pool = "nm"; fileP = 0 }
        else if path.contains("node_modules") { pool = "pkg"; fileP = 0.2 }
        else if nm == ".next" { pool = "next"; fileP = 0.1 }
        else if nm.contains("Movies") || nm == L10n.t("sample.disk.screenRecordings") { pool = "media"; fileP = 1 }
        else if ["Cache", "cache", "pnpm", "Homebrew", ".npm", "store"].contains(where: nm.contains) { pool = "cache"; fileP = 0.3 }

        let k = 3 + Int(r.next() * 5)
        let ws = (0..<k).map { _ in pow(r.next(), 2.2) + 0.03 }.sorted(by: >)
        let sum = ws.reduce(0, +)
        let media = L10n.t("sample.disk.media").components(separatedBy: "|")   // file names are in the selected language
        let names = shuffled(pool == "media" ? media : pools[pool]!, &r), fnames = shuffled(pools["files"]!, &r)
        var used = Set<String>()
        var kids: [DiskNode] = ws.enumerated().map { i, w in
            let size = n.size * 0.9 * w / sum
            let isFile = pool == "media" || (r.next() < fileP && size < n.size * 0.35)
            var name = (isFile && pool != "media" ? fnames[i % fnames.count] : names[i % names.count])
                .replacingOccurrences(of: "{n}", with: String(10 + Int(r.next() * 18)))
                .replacingOccurrences(of: "{h}", with: String(Int(r.next() * 0xFFFFF), radix: 16))
            while used.contains(name) { name += " 2" }
            used.insert(name)
            return DiskNode(name, size, file: isFile)
        }
        if n.size * 0.1 >= 0.004 { kids.append(DiskNode(L10n.t("disk.other"), n.size * 0.1)) }
        n.children = kids
    }

    private static func shuffled(_ a: [String], _ r: inout Mulberry32) -> [String] {
        var a = a
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, Int(r.next() * Double(i + 1))) }
        return a
    }

    private static func fnv1a(_ s: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for u in s.utf16 { h ^= UInt32(u); h = h &* 16_777_619 }
        return h
    }
}
