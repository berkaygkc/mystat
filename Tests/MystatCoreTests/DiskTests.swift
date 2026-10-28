import Foundation
import Testing
@testable import MystatCore

@MainActor @Suite struct DiskTests {
    @Test func basketRules() {
        let t = SampleSource(seed: 1).diskTree; var b = SelectionBasket()
        #expect(b.toggle(["Library", "Caches"], in: t) == .added)
        #expect(b.toggle(["Library", "Diğer"], in: t) == .notSelectable)
        #expect(b.toggle(["Library"], in: t) == .added)   // alt öğe düşer
        #expect(b.items.map(\.name) == ["Library"]); #expect(b.state(of: ["Library", "Caches"]) == .implied)
        #expect(b.toggle(["Library", "Caches"], in: t) == .blockedByAncestor)
        #expect(b.buttonTitle(mode: .permanent) == "Kalıcı olarak sil")
        #expect(b.confirmTitle(mode: .trash) == "Library çöpe taşınsın mı?")
        _ = b.toggle(["Downloads", "Xcode_26.2.xip"], in: t)
        #expect(b.buttonTitle(mode: .trash) == "2 öğeyi çöpe taşı"); #expect(b.confirmTitle(mode: .permanent) == "2 öğe kalıcı olarak silinsin mi?")
        #expect(abs(b.totalGB - 105.5) < 0.01)
        #expect(b.toggle(["Library"], in: t) == .removed); #expect(b.items.count == 1)
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
}
