import AppKit
import MystatCore
import MystatTestSupport
import Testing
@testable import MystatUI

/// The map's live model: path sync, clicks, keys, layout after deletion, scanning.
@MainActor @Suite(.language("tr")) struct BubbleMapModelTests {
    let size = CGSize(width: 655, height: 560)

    func make() -> (SampleSource, MonitorState, BubbleMapModel) {
        let src = SampleSource(seed: 1)
        let st = MonitorState()
        st.go(.disk)
        src.diskScan = .ready(scannedAt: Date())
        let m = BubbleMapModel(source: src, state: st)
        _ = m.frame(at: 0, size: size)
        return (src, st, m)
    }

    func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: code)!
    }

    func center(_ m: BubbleMapModel, _ name: String, at t: Double) -> CGPoint {
        let b = m.frame(at: t, size: size)!.mains.first { $0.item.name == name }!
        return CGPoint(x: b.x, y: b.y)
    }

    @Test func childPathZoomsInAndPrefixZoomsOut() {
        let (_, st, m) = make()
        st.disk.open(["Library"])
        #expect(m.frame(at: 0.1, size: size)?.membrane != nil)        // enter membrane
        _ = m.frame(at: 1.6, size: size)
        st.disk.open([])
        #expect(m.frame(at: 1.7, size: size)?.membrane != nil)        // exit membrane
        _ = m.frame(at: 3.2, size: size)
        #expect(m.frame(at: 3.3, size: size)?.membrane == nil)
    }

    @Test func unrelatedJumpIsInstant() {
        let (_, st, m) = make()
        st.disk.open(["Library", "Caches"])
        let f = m.frame(at: 0.1, size: size)!
        #expect(f.membrane == nil)
        #expect(f.mains.contains { $0.item.id.hasPrefix("Library/Caches/") })
    }

    /// Navigation arriving while the map is transitioning is ignored (a double-click on the sidebar list does not descend two levels).
    @Test func navigationIsIgnoredWhileTheMapAnimates() {
        let (_, st, m) = make()
        st.disk.open(["Library"])
        _ = m.frame(at: 0.1, size: size)
        #expect(st.disk.isMapAnimating)
        st.disk.open(["Library", "Containers"])                        // the second click of a double-click
        st.disk.open([])                                               // path row / Esc
        #expect(st.disk.path == ["Library"])
        #expect(m.frame(at: 0.2, size: size)?.membrane != nil)        // the running transition is not interrupted
        _ = m.frame(at: 1.6, size: size)
        _ = m.frame(at: 1.7, size: size)
        #expect(st.disk.isMapAnimating == false)
        st.disk.open([])
        #expect(st.disk.path.isEmpty)
    }

    /// A deletion confirmed during a transition does not interrupt it; the re-layout is deferred to the end.
    @Test func deleteDuringZoomKeepsTheZoom() async {
        let (src, st, m) = make()
        st.disk.open(["Library"])
        _ = m.frame(at: 0.1, size: size)
        st.disk.toggle([".npm"], tree: src.diskTree)
        await st.disk.performDelete(tree: src.diskTree, source: src)
        let f = m.frame(at: 0.5, size: size)!
        #expect(f.membrane != nil)
        #expect(f.mains.contains { $0.item.id.hasPrefix("Library/") } && f.mains.contains { $0.item.name == "Documents" })
        _ = m.frame(at: 1.6, size: size)
        #expect(st.disk.path == ["Library"])
    }

    /// No lock may remain when leaving the map (section changed).
    @Test func detachReleasesTheNavigationLock() {
        let (_, st, m) = make()
        st.disk.open(["Library"])
        _ = m.frame(at: 0.1, size: size)
        m.detach()
        #expect(st.disk.isMapAnimating == false)
    }

    @Test func clickOpensFolderAndCommandClickSelects() {
        let (_, st, m) = make()
        let p = center(m, "Library", at: 2), q = center(m, ".npm", at: 2)
        #expect(m.mouseMoved(p))                                       // pointing-hand cursor
        m.click(p, flags: [.command])
        #expect(st.disk.basket.isEmpty)                                // Library is protected
        _ = m.mouseMoved(q); m.click(q, flags: [.command])
        #expect(st.disk.basket.state(of: [".npm"]) == .selected)
        #expect(st.disk.path.isEmpty)
        _ = m.mouseMoved(p); m.click(p, flags: [])
        #expect(st.disk.path == ["Library"])
    }

    @Test func clickOnOtherDoesNothing() {
        let (_, st, m) = make()
        let p = center(m, "Diğer", at: 2)
        #expect(m.mouseMoved(p) == false)
        m.click(p, flags: [])
        m.click(p, flags: [.command])
        #expect(st.disk.path.isEmpty && st.disk.basket.isEmpty)
    }

    @Test func keysNavigateSelectAndAskToDelete() {
        let (_, st, m) = make()
        #expect(m.key(key(53)) == false)                              // Esc has nothing to do at the root
        #expect(m.key(key(51)) == false)                              // the basket is empty
        _ = m.mouseMoved(center(m, ".npm", at: 2))
        #expect(m.key(key(49)))                                        // Space
        #expect(st.disk.basket.state(of: [".npm"]) == .selected)
        #expect(m.key(key(49, .command)) == false)                    // not with ⌘
        #expect(m.key(key(51)))                                        // ⌫
        #expect(st.confirm != nil)
        st.disk.path = ["Library"]
        #expect(m.key(key(53)) == false)                              // while the confirmation is open, keys do not belong to the page
        st.confirm = nil
        #expect(m.key(key(53)))
        #expect(st.disk.path.isEmpty)
    }

    @Test func deletionRelayoutsWithRipple() async {
        let (src, st, m) = make()
        _ = m.frame(at: 2, size: size)
        st.disk.toggle([".npm"], tree: src.diskTree)
        await st.disk.performDelete(tree: src.diskTree, source: src)
        #expect(m.frame(at: 2.1, size: size)?.ripple != nil)          // ripple from the fading bubble
        _ = m.frame(at: 3.5, size: size)                               // in the last frame the fading bubble is drawn with alpha 0
        let f = m.frame(at: 3.6, size: size)!
        #expect(f.mains.contains { $0.item.name == ".npm" } == false)
    }

    @Test func deletingCurrentFolderJumpsUpWithoutZoom() async {
        let (src, st, m) = make()
        st.disk.open(["Library", "Caches"])
        _ = m.frame(at: 0.1, size: size)
        st.disk.toggle(["Library", "Caches"], tree: src.diskTree)
        await st.disk.performDelete(tree: src.diskTree, source: src)
        #expect(st.disk.path == ["Library"])
        let f = m.frame(at: 0.2, size: size)!
        #expect(f.membrane == nil)
        #expect(f.mains.contains { $0.item.name == "Containers" })
    }

    @Test func scanningGrowsThenSettles() {
        let (src, _, m) = make()
        let full = m.frame(at: 2, size: size)!.mains[0].r
        src.diskScan = .scanning(progress: 0.3, scannedGB: 50, currentPath: "~")
        let early = m.frame(at: 2, size: size)!.mains[0].r
        #expect(early < full * 0.5)
        src.diskScan = .ready(scannedAt: Date())
        var r = 0.0
        for i in 0..<120 { r = m.frame(at: 2 + Double(i) / 60, size: size)!.mains[0].r }
        #expect(abs(r - full) < 3)                                     // full size within the drift margin
    }

    @Test func overlayShowsLabelsAndSelectedButton() {
        let (src, st, m) = make()
        st.disk.toggle([".npm"], tree: src.diskTree)
        _ = m.frame(at: 2, size: size)
        #expect(m.labels.contains { $0.name == "Library" && $0.size == "96 GB" })
        #expect(m.buttons.map(\.path) == [[".npm"]])
        #expect(m.buttons.first?.state == .selected)
    }
    /// Labels snap to the device pixel; the slow drift at rest does not cause a SwiftUI update every frame.
    @Test func overlaySnapsToDevicePixels() {
        let (_, _, m) = make()
        m.pixelScale = 2
        var changes = 0, last: [BubbleLabel] = []
        for i in 0..<60 {
            _ = m.frame(at: 2 + Double(i) / 60, size: size)
            if m.labels != last { changes += 1; last = m.labels }
        }
        for l in m.labels { #expect(l.x * 2 == (l.x * 2).rounded() && l.y * 2 == (l.y * 2).rounded()) }
        #expect(changes < 30)
    }

    // MARK: Real scan

    /// During a live scan bubbles are not shrunk by simulation; the layout is redone as the tree grows.
    @Test func liveScanGrowsByRelayoutNotSimulation() throws {
        let src = SampleSource(seed: 1); src.diskScanSimulated = false
        let idx = ScanIndex(rootName: "~")
        let a = idx.addDirectory(parent: 0, name: "a", fileID: 1)
        idx.addFiles(dir: a, big: [], smallBytes: 5_000_000_000, smallCount: 1)
        let tree = DiskTree.scanned(idx); _ = tree.node(at: [])
        src.diskTree = tree
        src.diskScan = .scanning(progress: 0.3, scannedGB: 5, currentPath: "~")
        let st = MonitorState(); st.go(.disk)
        let m = BubbleMapModel(source: src, state: st)
        let scanning = try #require(m.frame(at: 0, size: size)?.mains.first?.r)
        src.diskScan = .ready(scannedAt: Date())
        let ready = try #require(BubbleMapModel(source: src, state: st).frame(at: 0, size: size)?.mains.first?.r)
        #expect(abs(scanning - ready) < 0.5)
        src.diskScan = .scanning(progress: 0.3, scannedGB: 5, currentPath: "~")
        let b = idx.addDirectory(parent: 0, name: "b", fileID: 2)
        idx.addFiles(dir: b, big: [], smallBytes: 3_000_000_000, smallCount: 1)
        tree.refresh()
        src.diskScan = .scanning(progress: 0.5, scannedGB: 8, currentPath: "~/b")
        _ = m.frame(at: 2.5, size: size)
        let f = try #require(m.frame(at: 4, size: size))
        #expect(Set(f.mains.map(\.item.name)) == ["a", "b"])
    }

    /// When the source's tree changes (scan started, loaded from cache) the map is rebuilt with the new tree; if the path is missing, it goes to the root.
    @Test func treeSwapRebuildsEngine() throws {
        let (src, st, m) = make()
        let idx = ScanIndex(rootName: "~")
        let x = idx.addDirectory(parent: 0, name: "x", fileID: 1)
        idx.addFiles(dir: x, big: [], smallBytes: 2_000_000_000, smallCount: 1)
        st.disk.path = ["Library"]
        _ = m.frame(at: 0.1, size: size)
        src.diskTree = DiskTree.scanned(idx)
        let f = try #require(m.frame(at: 0.2, size: size))
        #expect(f.mains.map(\.item.name) == ["x"])
        #expect(st.disk.path.isEmpty)
    }

    /// A protected folder's bubble shows a lock instead of ＋; the reason is in the tooltip.
    @Test func protectedBubbleShowsLock() {
        let (_, _, m) = make()
        _ = m.mouseMoved(center(m, "Library", at: 2))
        for i in 0..<40 { _ = m.frame(at: 2 + Double(i) / 60, size: size) }
        #expect(m.buttons.map(\.path) == [["Library"]])
        #expect(m.buttons.first?.locked == "Library macOS için gerekli; içindekileri seçebilirsin.")
        _ = m.mouseMoved(center(m, ".npm", at: 2.7))
        for i in 0..<40 { _ = m.frame(at: 2.7 + Double(i) / 60, size: size) }
        #expect(m.buttons.map(\.path) == [[".npm"]])
        #expect(m.buttons.first?.locked == nil)
    }

    @Test func deleteToastFromSource() async {
        let (src, st, _) = make()
        st.disk.toggle([".npm"], tree: src.diskTree)
        await st.disk.performDelete(tree: src.diskTree, source: src)
        #expect(ToastCenter.shared.message == "4,2 GB boşaldı (örnek)")
    }

    // MARK: Edge cases

    /// With a real "Other" folder present, Space on the small-files bubble selects nothing (so the wrong folder is not deleted).
    @Test func spaceOnSmallFilesBesideRealOtherSelectsNothing() throws {
        let src = SampleSource(seed: 1); src.diskScanSimulated = false
        let idx = ScanIndex(rootName: "~")
        let o = idx.addDirectory(parent: 0, name: "Diğer", fileID: 1)
        idx.addFiles(dir: o, big: [], smallBytes: 2_000_000_000, smallCount: 1)
        idx.addFiles(dir: 0, big: [], smallBytes: 3_000_000_000, smallCount: 7)
        src.diskTree = DiskTree.scanned(idx); src.diskScan = .ready(scannedAt: Date())
        let st = MonitorState(); st.go(.disk)
        let m = BubbleMapModel(source: src, state: st)
        let f = try #require(m.frame(at: 2, size: size))
        let small = try #require(f.mains.first { $0.item.kind == .other }), real = try #require(f.mains.first { $0.item.kind == .folder })
        _ = m.mouseMoved(CGPoint(x: small.x, y: small.y)); _ = m.key(key(49))
        #expect(st.disk.basket.isEmpty)
        _ = m.mouseMoved(CGPoint(x: real.x, y: real.y)); _ = m.key(key(49))
        #expect(st.disk.basket.items.map(\.size) == [2])
        #expect(Set(m.labels.compactMap(\.name)) == ["Diğer"])   // both show as "Other" on screen
    }

    /// When the section changes and comes back while the tree loads from cache, the path is kept (it does not jump to the root).
    @Test func placeholderTreeKeepsPath() throws {
        let src = SampleSource(seed: 1); src.diskScanSimulated = false
        let idx = ScanIndex(rootName: "~")
        let a = idx.addDirectory(parent: 0, name: "a", fileID: 1)
        let b = idx.addDirectory(parent: a, name: "b", fileID: 2)
        idx.addFiles(dir: b, big: [], smallBytes: 2_000_000_000, smallCount: 1)
        src.diskTree = DiskTree.scanned(idx); src.diskScan = .ready(scannedAt: Date())
        let st = MonitorState(); st.go(.disk); st.disk.path = ["a"]
        let m = BubbleMapModel(source: src, state: st)
        _ = m.frame(at: 0.1, size: size)
        src.diskTree = DiskTree(root: DiskNode("~", 0), provider: nil)   // loading
        _ = m.frame(at: 0.2, size: size)
        #expect(st.disk.path == ["a"])
        src.diskTree = DiskTree.scanned(idx)
        let f = try #require(m.frame(at: 0.3, size: size))
        #expect(st.disk.path == ["a"])
        #expect(f.mains.map(\.item.name) == ["b"])
    }

    /// Moving to the Trash does not free space: it is not added to "You freed X this session".
    @Test func trashDoesNotCountAsFreed() async {
        let (src, st, _) = make()
        st.disk.mode = .trash
        st.disk.toggle([".npm"], tree: src.diskTree)
        await st.disk.performDelete(tree: src.diskTree, source: src)
        #expect(st.disk.freedGB == 0)
        #expect(src.snapshot.disk.freeGB == 175)
        #expect(ToastCenter.shared.message == "4,2 GB çöpe taşındı (örnek)")
    }

    /// Deletion is not allowed while scanning; the selection is kept and the reason is shown.
    @Test func noDeleteWhileScanning() {
        let (src, st, _) = make()
        st.disk.toggle([".npm"], tree: src.diskTree)
        src.diskScan = .scanning(progress: 0.4, scannedGB: 90, currentPath: "~/Library")
        #expect(st.disk.confirmDelete(tree: src.diskTree, source: src) == nil)
        #expect(st.disk.basket.items.count == 1)
        #expect(ToastCenter.shared.message == "Tarama sürerken silinemez; bitince silebilirsin.")
    }
}
