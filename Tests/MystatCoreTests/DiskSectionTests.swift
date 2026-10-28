import Foundation
import Testing
@testable import MystatCore

@MainActor @Suite struct DiskSectionTests {
    @Test func headText() {
        let src = SampleSource(seed: 1)
        let h = SectionText.disk(src.snapshot, home: src.diskTree.root, freedGB: 0)
        #expect(h.title == "%62 dolu."); #expect(h.soft == "175 GB boş.")
        #expect(h.lede == "Ev klasörün 236 GB. En büyük kalem Library; içinde Docker'ın 27 GB'lık diski duruyor. Şu an diske en çok Docker yazıyor.")
        src.applyDeletion(gb: 24)
        let after = SectionText.disk(src.snapshot, home: DiskNode("Ev", 212, []), freedGB: 24)
        #expect(after.title == "%57 dolu."); #expect(after.soft == "199 GB boş.")
        #expect(after.lede == "Bu oturumda 24 GB yer açtın. Ev klasörün şu an 212 GB.")
    }
    @Test func deletionUpdatesSnapshot() {
        let src = SampleSource(seed: 1)
        src.applyDeletion(gb: 38)
        #expect(src.snapshot.disk.freeGB == 213); #expect(src.snapshot.disk.usedGB == 247); #expect(Int(src.snapshot.disk.percent.rounded()) == 54)
    }
    @Test func confirmMessages() {
        let t = SampleSource(seed: 1).diskTree; var b = SelectionBasket()
        _ = b.toggle(["Documents", "apps"], in: t)
        #expect(b.confirmMessage(mode: .permanent) == "31 GB yer hemen boşalacak. Bu işlem geri alınamaz.")
        _ = b.toggle(["Downloads", "Xcode_26.2.xip"], in: t); _ = b.toggle([".npm"], in: t); _ = b.toggle(["Library", "Caches"], in: t)
        #expect(b.confirmMessage(mode: .trash) == "apps, Caches, Xcode_26.2.xip ve 1 öğe daha. 59 GB çöpe gidecek; çöpü boşaltana kadar geri alabilirsin.")
    }

    @Test func accessNoteCases() {
        #expect(DiskPresentation.accessNote(fullDiskAccess: false, scanned: false, inaccessible: 0)
                == "Tam tarama için mystat'a Tam Disk Erişimi ver. Vermezsen korumalı klasörler atlanır.")
        #expect(DiskPresentation.accessNote(fullDiskAccess: true, scanned: false, inaccessible: 0) == nil)
        #expect(DiskPresentation.accessNote(fullDiskAccess: true, scanned: true, inaccessible: 0) == nil)
        #expect(DiskPresentation.accessNote(fullDiskAccess: true, scanned: true, inaccessible: 144) == "144 klasör okunamadı (macOS korumalı)")
        #expect(DiskPresentation.accessNote(fullDiskAccess: false, scanned: true, inaccessible: 1_440) == "1.440 klasör okunamadı (macOS korumalı)")
    }

    /// Gerçek taramada cümle ağaçtan kurulur; örnek verideki "en çok yazan" yalnızca veri varsa.
    @Test func ledeFromScannedTree() {
        var s = SampleSource(seed: 1).snapshot
        s.disk.topWriter = nil
        let idx = ScanIndex(rootName: "~")
        let lib = idx.addDirectory(parent: 0, name: "Library", fileID: 1)
        idx.addFiles(dir: lib, big: [], smallBytes: 60_000_000_000, smallCount: 1)
        let doc = idx.addDirectory(parent: 0, name: "Documents", fileID: 2)
        idx.addFiles(dir: doc, big: [], smallBytes: 20_000_000_000, smallCount: 1)
        let t = DiskTree.scanned(idx); _ = t.node(at: [])
        s.docker.disk.rawGB = 27
        #expect(SectionText.disk(s, home: t.root, freedGB: 0).lede == "Ev klasörün 80 GB. En büyük kalem Library; içinde Docker'ın 27 GB'lık diski duruyor.")
        s.capabilities = SourceCapabilities(docker: false, sensors: true, diskScan: true, netDetails: true)
        #expect(SectionText.disk(s, home: t.root, freedGB: 0).lede == "Ev klasörün 80 GB. En büyük kalem Library.")
        #expect(SectionText.disk(s, home: nil, freedGB: 0).lede == "Sistem gerektiğinde 12 GB'ı kendiliğinden boşaltabilir.")
        #expect(SectionText.disk(s, home: DiskNode("~", 0), freedGB: 0).lede == "Sistem gerektiğinde 12 GB'ı kendiliğinden boşaltabilir.")
    }
}
