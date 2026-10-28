import Foundation

public enum NodeKind: Sendable, Equatable { case folder, regen, docker, file, other }

/// Disk ağacının bir düğümü. Boyut GB cinsinden.
public final class DiskNode {
    public let name: String
    public var size: Double
    public let isFile: Bool
    public let isDocker: Bool
    public var children: [DiskNode]?

    public init(_ name: String, _ size: Double, file: Bool = false, docker: Bool = false, _ children: [DiskNode]? = nil) {
        self.name = name; self.size = size; self.isFile = file; self.isDocker = docker; self.children = children
    }

    /// Tür = renk (spec §6.4). Mockup'taki `kindOf`.
    public var kind: NodeKind {
        if isDocker || name == "Docker" { return .docker }
        if name == "Diğer" { return .other }
        if name.prefixMatch(of: Self.regen) != nil { return .regen }
        if isFile { return .file }
        return .folder
    }

    /// İçine girilebilir mi (örnek veride alt düğüm üretilebilir mi).
    public var canHaveChildren: Bool { !isFile && name != "Diğer" && size >= 0.03 }

    nonisolated(unsafe) static let regen = /(node_modules|\.next|Caches|DerivedData|pnpm|Homebrew|\.npm|\.cache)/
}

public final class DiskTree {
    public let root: DiskNode
    public init(root: DiskNode) { self.root = root }

    /// Yol boyunca örnek alt düğümleri tembelce üreterek düğümü bulur.
    public func node(at path: [String]) -> DiskNode? {
        var n = root
        SampleGenerator.generate(n, path: [])
        for (i, name) in path.enumerated() {
            guard let next = n.children?.first(where: { $0.name == name }) else { return nil }
            n = next
            SampleGenerator.generate(n, path: Array(path[...i]))
        }
        return n
    }

    /// Düğümü ağaçtan çıkarır, atalarının boyutunu düşer; silinen boyutu döner.
    @discardableResult
    public func remove(at path: [String]) -> Double {
        guard let last = path.last, let parent = node(at: Array(path.dropLast())),
              let i = parent.children?.firstIndex(where: { $0.name == last }) else { return 0 }
        let size = parent.children![i].size
        parent.children!.remove(at: i)
        var n = root
        n.size -= size
        for name in path.dropLast() {
            n = n.children!.first { $0.name == name }!
            n.size -= size
        }
        return size
    }
}

/// Örnek veride sınırsız derinlik için yola bağlı, deterministik alt düğüm üretimi (mockup'taki `genKids`).
enum SampleGenerator {
    static let pools: [String: [String]] = [
        "nm": ["next", "@next", "typescript", "@swc", "esbuild", "react-dom", "@prisma", "turbo", "sharp", "lightningcss", "@img", "playwright-core", "@babel", "webpack", "caniuse-lite", "date-fns", "lodash", "@tanstack", "rxjs", "zod"],
        "pkg": ["dist", "lib", "cjs", "esm", "node_modules", "bin", "src", "types", "vendor"],
        "next": ["cache", "server", "static", "standalone", "types", "webpack", "swc"],
        "media": ["Ekran Kaydı 2026-10-{n}.mov", "Toplantı {n}.mp4", "Demo {n}.mov", "Sunum kaydı {n}.mp4", "Klip {n}.mov"],
        "cache": ["com.apple.{h}", "v3", "blobs", "index", "tmp", "store-{h}", "metadata", "objects"],
        "gen": ["src", "assets", "build", "dist", "logs", "data", "backup", "archive", "cache", ".git", "exports", "vendor", "public", "tests", "scripts", "models", "fixtures", "raw", "temp"],
        "files": ["export.zip", "dump.sql", "video.mp4", "dataset.parquet", "backup.tar.gz", "model.bin", "image.dmg", "recording.mov", "events.log", "archive.7z", "bundle.js.map", "snapshot.db"],
    ]

    static func generate(_ n: DiskNode, path: [String]) {
        guard n.children == nil, n.canHaveChildren else { return }
        var r = Mulberry32(seed: fnv1a(path.joined(separator: "/") + "#"))
        let nm = n.name
        var pool = "gen", fileP = 0.28
        if nm.hasPrefix("node_modules") { pool = "nm"; fileP = 0 }
        else if path.contains("node_modules") { pool = "pkg"; fileP = 0.2 }
        else if nm == ".next" { pool = "next"; fileP = 0.1 }
        else if nm.contains("Movies") || nm.contains("Kayıt") || nm.contains("Klip") { pool = "media"; fileP = 1 }
        else if ["Cache", "cache", "pnpm", "Homebrew", ".npm", "store"].contains(where: nm.contains) { pool = "cache"; fileP = 0.3 }

        let k = 3 + Int(r.next() * 5)
        let ws = (0..<k).map { _ in pow(r.next(), 2.2) + 0.03 }.sorted(by: >)
        let sum = ws.reduce(0, +)
        let names = shuffled(pools[pool]!, &r), fnames = shuffled(pools["files"]!, &r)
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
        if n.size * 0.1 >= 0.004 { kids.append(DiskNode("Diğer", n.size * 0.1)) }
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
