import CoreGraphics
import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

@MainActor @Suite(.language("tr")) struct BubbleEngineTests {
    let size = CGSize(width: 655, height: 560)

    @Test func layoutMatchesMockupGeometry() {
        let e = BubbleEngine(tree: SampleSource(seed: 1).diskTree, path: [], viewSize: size)
        #expect(e.items.first?.name == "Library")
        // R0 = min(655, 514)/2 − 22 = 235; tüm balonlar kök dairesinin içinde
        for it in e.items { #expect(hypot(it.x - 327.5, it.y - 265) + it.r <= 235 + 1e-6) }
    }
    @Test func zoomInLandsExactly() {
        let e = BubbleEngine(tree: SampleSource(seed: 1).diskTree, path: [], viewSize: size)
        #expect(e.zoomIn("Library", at: 0)); #expect(e.zoomIn("Documents", at: 0.1) == false)   // animasyon sürerken yok sayılır
        _ = e.frame(at: 1.4, hover: nil, selection: { _ in .none })
        #expect(e.path == ["Library"]); #expect(e.isAnimating == false)
        let target = BubbleEngine(tree: SampleSource(seed: 1).diskTree, path: ["Library"], viewSize: size).items
        for (a, b) in zip(e.items, target) { #expect(abs(a.x - b.x) < 0.5 && abs(a.r - b.r) < 0.5) }
    }
    @Test func zoomCameraLandsChildrenOnTheirLayout() {
        let e = BubbleEngine(tree: SampleSource(seed: 1).diskTree, path: [], viewSize: size)
        _ = e.zoomIn("Library", at: 0)
        let f = e.frame(at: 1.3999, hover: nil, selection: { _ in .none })
        let target = BubbleEngine(tree: SampleSource(seed: 1).diskTree, path: ["Library"], viewSize: size).items
        let containers = f.mains.first { $0.item.name == "Containers" }!
        let ref = target.first { $0.name == "Containers" }!
        #expect(abs(containers.r - ref.r) < 1.0); #expect(f.membrane != nil)
    }
    @Test func deleteDuringZoomIsDeferred() {
        let tree = SampleSource(seed: 1).diskTree
        let e = BubbleEngine(tree: tree, path: ["Documents"], viewSize: size)
        e.zoomIn("apps", at: 0); tree.remove(at: ["Documents", "apps", "acmecorp"]); e.relayout(at: 0.5)
        _ = e.frame(at: 1.5, hover: nil, selection: { _ in .none }); _ = e.frame(at: 2.6, hover: nil, selection: { _ in .none })
        #expect(e.items.map(\.name) == ["Diğer"])
    }
    @Test func multiLevelZoomOut() {
        let e = BubbleEngine(tree: SampleSource(seed: 1).diskTree, path: ["Library", "Containers", "Docker"], viewSize: size)
        e.zoomOut(to: [], at: 0); var t = 0.0
        while e.isAnimating && t < 10 { t += 1.0 / 60; _ = e.frame(at: t, hover: nil, selection: { _ in .none }) }
        #expect(e.path == []); #expect(t < 0.8 * 2 + 1.25 + 0.1)
    }
    @Test func labels() {
        let e = BubbleEngine(tree: SampleSource(seed: 1).diskTree, path: ["Library"], viewSize: size)
        let a = e.items.first { $0.name == "Application Support" }!
        #expect(e.labelText(for: a, radius: 40)?.name == "Applicat…")   // mockup: slice(0, floor(r/4,4) − 1) + "…"
        #expect(e.labelText(for: a, radius: 20)?.name == nil); #expect(e.labelText(for: a, radius: 20)?.size == "28 GB")
        #expect(e.labelText(for: a, radius: 10) == nil)
    }
    @Test func selectionAndHitTest() {
        let e = BubbleEngine(tree: SampleSource(seed: 1).diskTree, path: [], viewSize: size)
        let f = e.frame(at: 0, hover: nil, selection: { $0 == ["Library"] ? .selected : .none })
        #expect(f.mains.first { $0.item.name == "Library" }?.selection == 1)
        let lib = f.mains.first { $0.item.name == "Library" }!
        #expect(e.hitTest(CGPoint(x: lib.x, y: lib.y), current: nil)?.name == "Library")
        #expect(e.hitTest(CGPoint(x: 2, y: 2), current: nil) == nil)
    }
    /// Tarama sürerken balonlar yerinde büyür (spec §6.4 "Tarama sırasında"); bitince tam boyda.
    @Test func scanGrowsBubblesInPlace() {
        let e = BubbleEngine(tree: SampleSource(seed: 1).diskTree, path: [], viewSize: size)
        let full = e.frame(at: 2, hover: nil, selection: { _ in .none })
        e.scanProgress = 0.3
        let part = e.frame(at: 2, hover: nil, selection: { _ in .none })
        for (a, b) in zip(full.mains, part.mains) {
            #expect(abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9)
            #expect(b.r > 0 && b.r < a.r)
        }
        #expect(part.droplets.count == full.droplets.count)
        #expect(part.droplets[0].r < full.droplets[0].r)
        e.scanProgress = 1
        let done = e.frame(at: 2, hover: nil, selection: { _ in .none })
        for (a, b) in zip(full.mains, done.mains) { #expect(abs(a.r - b.r) < 1e-9) }
        #expect(BubbleEngine.scanGrowth(phase: 0.9, progress: 1) == 1)
        #expect(BubbleEngine.scanGrowth(phase: 0.2, progress: 0) > 0)
    }
    /// Kenar listesi taramada haritadaki etiketle aynı birikmiş boyutu gösterir.
    @Test func scannedSizeMatchesBubbleGrowth() {
        let e = BubbleEngine(tree: SampleSource(seed: 1).diskTree, path: [], viewSize: size)
        let lib = e.items.first { $0.name == "Library" }!
        #expect(BubbleEngine.scannedSize(96, path: ["Library"], progress: 0.3) == 96 * BubbleEngine.scanGrowth(phase: lib.phase, progress: 0.3))
        #expect(BubbleEngine.scannedSize(96, path: ["Library"], progress: nil) == 96)
    }
    /// Tarama satırındaki "Taranıyor · X GB" kenar listesinin toplamıyla aynı.
    @Test func scannedTotalIsSumOfRootRows() {
        let t = SampleSource(seed: 1).diskTree
        let rows = (t.root.children ?? []).reduce(0) { $0 + BubbleEngine.scannedSize($1.size, path: [$1.name], progress: 0.55) }
        #expect(abs(BubbleEngine.scannedTotal(t, progress: 0.55) - rows) < 1e-9)
        #expect(BubbleEngine.scannedTotal(t, progress: 0.55) < t.root.size)
    }

    @Test func layoutCapsAt24() throws {
        let idx = ScanIndex(rootName: "~")
        for i in 1...30 {
            let d = idx.addDirectory(parent: 0, name: "d\(i)", fileID: UInt64(i))
            idx.addFiles(dir: d, big: [], smallBytes: Int64(i) * 100_000_000, smallCount: 1)
        }
        idx.addFiles(dir: 0, big: [], smallBytes: 50_000_000, smallCount: 10)
        let e = BubbleEngine(tree: DiskTree.scanned(idx), path: [], viewSize: size)
        #expect(e.items.count == BubbleEngine.maxBubbles)
        #expect(Set(e.items.filter { $0.kind != .other }.map(\.name)) == Set((8...30).map { "d\($0)" }))
        let rest = try #require(e.items.first { $0.kind == .other })
        #expect(abs(rest.size - 2.85) < 1e-9)   // d1…d7 (2,8 GB) + küçük dosyalar 50 MB
        #expect(rest.hasChildren == false); #expect(DiskNode.display(rest.name) == "Diğer")
        #expect(e.zoomIn(rest.name, at: 0) == false)
    }
}

