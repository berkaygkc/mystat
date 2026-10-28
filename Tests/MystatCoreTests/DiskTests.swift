import Foundation
import Testing
@testable import MystatCore

@MainActor @Suite struct DiskTests {
    @Test func basketRules() {
        let t = SampleSource(seed: 1).diskTree; var b = SelectionBasket()
        #expect(b.toggle(["Documents", "apps", "acmecorp"], in: t) == .added)
        #expect(b.toggle(["Documents", "apps", "Diğer"], in: t) == .notSelectable)
        #expect(b.toggle(["Documents", "apps"], in: t) == .added)   // alt öğe düşer
        #expect(b.items.map(\.name) == ["apps"]); #expect(b.state(of: ["Documents", "apps", "acmecorp"]) == .implied)
        #expect(b.toggle(["Documents", "apps", "acmecorp"], in: t) == .blockedByAncestor)
        #expect(b.buttonTitle(mode: .permanent) == "Kalıcı olarak sil")
        #expect(b.confirmTitle(mode: .trash) == "apps çöpe taşınsın mı?")
        _ = b.toggle(["Downloads", "Xcode_26.2.xip"], in: t)
        #expect(b.buttonTitle(mode: .trash) == "2 öğeyi çöpe taşı"); #expect(b.confirmTitle(mode: .permanent) == "2 öğe kalıcı olarak silinsin mi?")
        #expect(abs(b.totalGB - 40.5) < 0.01)
        #expect(b.toggle(["Documents", "apps"], in: t) == .removed); #expect(b.items.count == 1)
    }
    @Test func kinds() {
        let t = SampleSource(seed: 1).diskTree
        #expect(t.node(at: ["Library", "Caches"])?.kind == .regen)
        #expect(t.node(at: ["Library", "Containers", "Docker"])?.kind == .docker)
        #expect(t.node(at: ["Downloads", "Xcode_26.2.xip"])?.kind == .file)
        #expect(t.node(at: ["Diğer"])?.kind == .other)
        #expect(t.node(at: ["Documents"])?.kind == .folder)
    }
    @Test func removeUpdatesAncestors() {
        let t = SampleSource(seed: 1).diskTree
        #expect(t.remove(at: ["Documents", "apps", "acmecorp"]) == 24)
        #expect(t.node(at: ["Documents"])?.size == 28); #expect(t.root.size == 212)
        #expect(t.node(at: ["Documents", "apps", "acmecorp"]) == nil)
    }
    @Test func lazyDepth() {
        let t = SampleSource(seed: 1).diskTree; var path = ["Documents", "apps", "acmecorp", "node_modules"]; var depth = 4
        while let n = t.node(at: path), let next = n.children?.filter({ $0.kind != .other && !$0.isFile && $0.size >= 0.03 }).max(by: { $0.size < $1.size }) {
            path.append(next.name); depth += 1
        }
        #expect(depth >= 7)
        let other = SampleSource(seed: 99).diskTree   // üretim tohuma değil yola bağlı: aynı yol aynı çocuklar
        #expect(t.node(at: path)?.children?.map(\.name) == other.node(at: path)?.children?.map(\.name))
        let kids = t.node(at: ["Documents", "apps", "acmecorp", "node_modules"])!.children!
        #expect(abs(kids.reduce(0) { $0 + $1.size } - 11.2) < 1e-9)   // çocuklar ebeveyni tam doldurur
    }
    @Test func crumbs() {
        let c = Breadcrumbs.make(["a", "b", "c", "d", "e", "f", "g"])
        #expect(c.map(\.name) == ["Ev", "…", "d", "e", "f", "g"]); #expect(c[1].path == ["a", "b", "c"]); #expect(c[1].isEllipsis)
        #expect(Breadcrumbs.make(["a", "b"]).map(\.name) == ["Ev", "a", "b"])
    }
    @Test func scanValidity() {
        let t0 = Date(timeIntervalSince1970: 0)
        #expect(ScanPhase.ready(scannedAt: t0).validityText(now: t0 + 18 * 60) == "Tarama 42 dk daha geçerli")
        #expect(ScanPhase.ready(scannedAt: t0).effective(now: t0 + 3600) == .none)
        #expect(ScanPhase.ready(scannedAt: t0).validityText(now: t0 + 3600) == nil)
    }
    /// Tohum mockup'taki gibi `floor(hash01(yol + "#") · 1e9) + 11`; boyutlar (karıştırmadan önce çekilir)
    /// tarayıcıdan bağımsız olarak mockup `genKids` ile aynı olmalı (WebKit dökümünden).
    @Test func generatedSizesMatchMockup() {
        let t = SampleSource(seed: 1).diskTree
        let expected: [String: [Double]] = [
            "Movies": [3.6873, 3.0061, 0.4029, 0.3837, 0.3094, 0.1893, 0.1213, 0.9],
            "Pictures": [2.4058, 1.5922, 0.6190, 0.6117, 0.1713, 0.6],
            ".npm": [1.4177, 1.3530, 0.6081, 0.3262, 0.0749, 0.42],
            ".cache": [1.3842, 0.6933, 0.4281, 0.2845, 0.31],
        ]
        for (name, sizes) in expected {
            let got = t.node(at: [name])?.children?.map(\.size) ?? []
            #expect(got.count == sizes.count, "\(name)")
            for (a, b) in zip(got, sizes) { #expect(abs(a - b) < 0.0001, "\(name)") }
        }
    }

    // MARK: Tarama ağacı (Faz 2d)

    static let MB: Int64 = 1_000_000

    /// kök → a(50) → a/b(40 + x 20), kök → c(30 + y 15). Toplam 155 MB.
    static func scanIndex() -> (ScanIndex, a: Int32, b: Int32, c: Int32) {
        let idx = ScanIndex(rootName: "~")
        let a = idx.addDirectory(parent: 0, name: "a", fileID: 1)
        idx.addFiles(dir: a, big: [], smallBytes: 50 * MB, smallCount: 5)
        let b = idx.addDirectory(parent: a, name: "b", fileID: 2)
        idx.addFiles(dir: b, big: [(name: "x", bytes: 20 * MB, fileID: 10)], smallBytes: 40 * MB, smallCount: 4)
        let c = idx.addDirectory(parent: 0, name: "c", fileID: 3)
        idx.addFiles(dir: c, big: [(name: "y", bytes: 15 * MB, fileID: 11)], smallBytes: 30 * MB, smallCount: 3)
        return (idx, a, b, c)
    }

    @Test func scannedTreeLazy() throws {
        let (idx, a, _, _) = Self.scanIndex()
        let t = DiskTree.scanned(idx)
        #expect(abs(t.root.size - 0.155) < 1e-9)
        let na = try #require(t.node(at: ["a"]))
        #expect(na.children?.map(\.name) == idx.children(of: a, totals: idx.totals()).map(\.name))
        #expect(na.children?.map(\.name) == ["b", "Diğer"])
        #expect(t.root.children?.first { $0.name == "c" }?.children == nil)   // açılmayan dal
        #expect(t.node(at: ["a", "b", "x"])?.isFile == true)
        #expect(t.node(at: ["a", "b", "x"])?.fileID == 10)
        #expect(t.node(at: ["a", "b"])?.fileID == 2)
    }

    @Test func refreshKeepsIdentity() throws {
        let (idx, a, _, _) = Self.scanIndex()
        let t = DiskTree.scanned(idx)
        let na = try #require(t.node(at: ["a"]))
        idx.addFiles(dir: a, big: [], smallBytes: 10 * Self.MB, smallCount: 1)
        let d = idx.addDirectory(parent: 0, name: "d", fileID: 9)
        idx.addFiles(dir: d, big: [], smallBytes: 5 * Self.MB, smallCount: 1)
        t.refresh()
        #expect(t.node(at: ["a"]) === na)
        #expect(abs(na.size - 0.12) < 1e-9)
        #expect(abs(t.root.size - 0.17) < 1e-9)
        #expect(t.root.children?.contains { $0.name == "d" } == true)
        if case .other(let n)? = na.children?.first(where: { $0.name == "Diğer" })?.ref { #expect(n == 6) } else { Issue.record("Diğer yok") }
    }

    @Test func otherIsNotEnterable() {
        let (idx, _, _, _) = Self.scanIndex()
        let t = DiskTree.scanned(idx); var b = SelectionBasket()
        #expect(b.toggle(["a", "Diğer"], in: t) == .notSelectable)
        #expect(t.node(at: ["a", "Diğer"])?.kind == .other)
        #expect(t.node(at: ["a", "Diğer"])?.canHaveChildren == false)
        #expect(b.toggle(["a", "b"], in: t) == .added)
    }

    @Test func realFolderNamedOtherIsFolder() throws {
        let idx = ScanIndex(rootName: "~")
        let o = idx.addDirectory(parent: 0, name: "Diğer", fileID: 1)
        let z = idx.addDirectory(parent: o, name: "z", fileID: 2)
        idx.addFiles(dir: z, big: [], smallBytes: 40 * Self.MB, smallCount: 1)
        let t = DiskTree.scanned(idx)
        let n = try #require(t.node(at: ["Diğer"]))
        #expect(n.kind == .folder); #expect(n.canHaveChildren)
        #expect(t.node(at: ["Diğer", "z"]) != nil)
    }

    @Test func dockerPathMarked() {
        let idx = ScanIndex(rootName: "~")
        var parent: Int32 = 0
        for (i, name) in ["Library", "Containers", "com.docker.docker", "Data", "vms", "0", "data"].enumerated() {
            parent = idx.addDirectory(parent: parent, name: name, fileID: UInt64(i + 1))
        }
        idx.addFiles(dir: parent, big: [(name: "Docker.raw", bytes: 30_000 * Self.MB, fileID: 99)], smallBytes: 0, smallCount: 0)
        let t = DiskTree.scanned(idx)
        #expect(t.node(at: ["Library", "Containers", "com.docker.docker", "Data", "vms", "0", "data", "Docker.raw"])?.kind == .docker)
        #expect(t.node(at: ["Library", "Containers", "com.docker.docker"])?.kind == .docker)
        #expect(t.node(at: ["Library", "Containers"])?.kind == .folder)
    }

    @Test func removeUpdatesIndex() throws {
        let (idx, _, _, _) = Self.scanIndex()
        let t = DiskTree.scanned(idx)
        _ = t.node(at: ["a", "b"]); _ = t.node(at: ["c", "y"])
        #expect(abs(t.remove(at: ["a", "b"]) - 0.06) < 1e-9)
        #expect(abs(t.remove(at: ["c", "y"]) - 0.015) < 1e-9)
        #expect(abs(t.root.size - 0.08) < 1e-9)
        let t2 = DiskTree.scanned(idx)
        #expect(abs(t2.root.size - 0.08) < 1e-9)
        #expect(t2.node(at: ["a"])?.children?.map(\.name) == ["Diğer"])
        #expect(t2.node(at: ["c"])?.children?.map(\.name) == ["Diğer"])
    }

    @Test func shrinkReducesNodeAndAncestors() throws {
        let (idx, _, _, _) = Self.scanIndex()
        let t = DiskTree.scanned(idx)
        let b = try #require(t.node(at: ["a", "b"]))
        t.shrink(at: ["a", "b"], by: 0.02)
        #expect(abs(b.size - 0.04) < 1e-9)
        #expect(abs((t.node(at: ["a"])?.size ?? 0) - 0.09) < 1e-9)
        #expect(abs(t.root.size - 0.135) < 1e-9)
    }
}

