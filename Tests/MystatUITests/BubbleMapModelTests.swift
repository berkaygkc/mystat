import AppKit
import MystatCore
import Testing
@testable import MystatUI

/// Haritanın canlı modeli: yol eşitleme, tıklama, tuşlar, silme sonrası yerleşim, tarama.
@MainActor @Suite struct BubbleMapModelTests {
    let size = CGSize(width: 655, height: 560)

    func make() -> (SampleSource, MonitorState, BubbleMapModel) {
        let src = SampleSource(seed: 1)
        let st = MonitorState()
        st.go(.disk)
        st.disk.scan = .ready(scannedAt: Date())
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
        #expect(m.frame(at: 0.1, size: size)?.membrane != nil)        // içine girme zarı
        _ = m.frame(at: 1.6, size: size)
        st.disk.open([])
        #expect(m.frame(at: 1.7, size: size)?.membrane != nil)        // geri çıkış zarı
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

    /// Mockup `openDisk`: harita geçiş yaparken gelen gezinme yok sayılır (kenar listesine çift tıklama iki seviye indirmez).
    @Test func navigationIsIgnoredWhileTheMapAnimates() {
        let (_, st, m) = make()
        st.disk.open(["Library"])
        _ = m.frame(at: 0.1, size: size)
        #expect(st.disk.isMapAnimating)
        st.disk.open(["Library", "Containers"])                        // çift tıklamanın ikincisi
        st.disk.open([])                                               // yol satırı / Esc
        #expect(st.disk.path == ["Library"])
        #expect(m.frame(at: 0.2, size: size)?.membrane != nil)        // süren geçiş kesilmez
        _ = m.frame(at: 1.6, size: size)
        _ = m.frame(at: 1.7, size: size)
        #expect(st.disk.isMapAnimating == false)
        st.disk.open([])
        #expect(st.disk.path.isEmpty)
    }

    /// Geçiş sırasında onaylanan silme geçişi kesmez; yeniden yerleşim sona kalır (Review Focus #4).
    @Test func deleteDuringZoomKeepsTheZoom() {
        let (src, st, m) = make()
        st.disk.open(["Library"])
        _ = m.frame(at: 0.1, size: size)
        st.disk.toggle(["Movies"], tree: src.diskTree)
        st.disk.performDelete(tree: src.diskTree, source: src)
        let f = m.frame(at: 0.5, size: size)!
        #expect(f.membrane != nil)
        #expect(f.mains.contains { $0.item.id.hasPrefix("Library/") } && f.mains.contains { $0.item.name == "Documents" })
        _ = m.frame(at: 1.6, size: size)
        #expect(st.disk.path == ["Library"])
    }

    /// Haritadan ayrılınca (bölüm değişti) kilit kalmamalı.
    @Test func detachReleasesTheNavigationLock() {
        let (_, st, m) = make()
        st.disk.open(["Library"])
        _ = m.frame(at: 0.1, size: size)
        m.detach()
        #expect(st.disk.isMapAnimating == false)
    }

    @Test func clickOpensFolderAndCommandClickSelects() {
        let (_, st, m) = make()
        let p = center(m, "Library", at: 2)
        #expect(m.mouseMoved(p))                                       // el imleci
        m.click(p, flags: [.command])
        #expect(st.disk.basket.state(of: ["Library"]) == .selected)
        #expect(st.disk.path.isEmpty)
        m.click(p, flags: [])
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
        #expect(m.key(key(53)) == false)                              // kökte Esc'nin işi yok
        #expect(m.key(key(51)) == false)                              // sepet boş
        _ = m.mouseMoved(center(m, "Documents", at: 2))
        #expect(m.key(key(49)))                                        // Space
        #expect(st.disk.basket.state(of: ["Documents"]) == .selected)
        #expect(m.key(key(49, .command)) == false)                    // ⌘ ile değil
        #expect(m.key(key(51)))                                        // ⌫
        #expect(st.confirm != nil)
        st.disk.path = ["Library"]
        #expect(m.key(key(53)) == false)                              // onay açıkken tuşlar sayfaya ait değil
        st.confirm = nil
        #expect(m.key(key(53)))
        #expect(st.disk.path.isEmpty)
    }

    @Test func deletionRelayoutsWithRipple() {
        let (src, st, m) = make()
        _ = m.frame(at: 2, size: size)
        st.disk.toggle(["Movies"], tree: src.diskTree)
        st.disk.performDelete(tree: src.diskTree, source: src)
        #expect(m.frame(at: 2.1, size: size)?.ripple != nil)          // sönen balondan dalga
        _ = m.frame(at: 3.5, size: size)                               // son karede sönen balon alfa 0 ile çizilir
        let f = m.frame(at: 3.6, size: size)!
        #expect(f.mains.contains { $0.item.name == "Movies" } == false)
    }

    @Test func deletingCurrentFolderJumpsUpWithoutZoom() {
        let (src, st, m) = make()
        st.disk.open(["Library", "Caches"])
        _ = m.frame(at: 0.1, size: size)
        st.disk.toggle(["Library", "Caches"], tree: src.diskTree)
        st.disk.performDelete(tree: src.diskTree, source: src)
        #expect(st.disk.path == ["Library"])
        let f = m.frame(at: 0.2, size: size)!
        #expect(f.membrane == nil)
        #expect(f.mains.contains { $0.item.name == "Containers" })
    }

    @Test func scanningGrowsThenSettles() {
        let (_, st, m) = make()
        let full = m.frame(at: 2, size: size)!.mains[0].r
        st.disk.scan = .scanning(progress: 0.3, scannedGB: 50, currentPath: "~")
        let early = m.frame(at: 2, size: size)!.mains[0].r
        #expect(early < full * 0.5)
        st.disk.scan = .ready(scannedAt: Date())
        var r = 0.0
        for i in 0..<120 { r = m.frame(at: 2 + Double(i) / 60, size: size)!.mains[0].r }
        #expect(abs(r - full) < 3)                                     // süzülme payı içinde tam boy
    }

    @Test func overlayShowsLabelsAndSelectedButton() {
        let (src, st, m) = make()
        st.disk.toggle(["Library"], tree: src.diskTree)
        _ = m.frame(at: 2, size: size)
        #expect(m.labels.contains { $0.name == "Library" && $0.size == "96 GB" })
        #expect(m.buttons.map(\.path) == [["Library"]])
        #expect(m.buttons.first?.state == .selected)
    }
    /// Etiketler cihaz pikseline oturur; dinlenmedeki yavaş süzülme her karede SwiftUI güncellemesi doğurmaz.
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
}
