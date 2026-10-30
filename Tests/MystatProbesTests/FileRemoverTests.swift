import Darwin
import Foundation
import Testing
@testable import MystatProbes

@Suite struct FileRemoverTests {
    static func ino(_ url: URL) -> UInt64 {
        var st = stat(); _ = lstat(url.path, &st); return UInt64(st.st_ino)
    }
    var exists: (URL) -> Bool { { FileManager.default.fileExists(atPath: $0.path) } }

    @Test func removePermanent() throws {
        let fx = try ScanFixture()
        try fx.dir("silinecek/iç"); try fx.file("silinecek/a.bin", bytes: 2_000_000); try fx.file("silinecek/iç/b.bin", bytes: 1_000_000)
        let url = fx.root.appendingPathComponent("silinecek")
        let du = try ScanFixture.du(url.path)
        let r = FileRemover.remove(url, expectedFileID: Self.ino(url), toTrash: false)
        guard case .removed(let bytes) = r else { Issue.record("\(r)"); return }
        #expect(abs(Double(bytes - du)) <= Double(du) * 0.01)
        #expect(!exists(url))
    }

    @Test func removeToTrashUsesTrash() throws {
        let fx = try ScanFixture(), bin = try ScanFixture()
        try fx.file("çöpe.bin", bytes: 1_000_000)
        let url = fx.root.appendingPathComponent("çöpe.bin")
        let r = FileRemover.remove(url, expectedFileID: Self.ino(url), toTrash: true) { item in
            try FileManager.default.moveItem(at: item, to: bin.root.appendingPathComponent(item.lastPathComponent))
        }
        guard case .removed(let bytes) = r else { Issue.record("\(r)"); return }
        #expect(bytes >= 1_000_000)
        #expect(!exists(url)); #expect(exists(bin.root.appendingPathComponent("çöpe.bin")))
    }

    /// Real trash: a temporary folder inside the home directory; the result goes to `~/.Trash`. It does not run in the default bundle, so it leaves no trace in the user's trash.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MYSTAT_TRASH_TEST"] != nil))
    func removeToRealTrash() throws {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("mystat-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(count: 100_000).write(to: url.appendingPathComponent("a.bin"))
        let r = FileRemover.remove(url, expectedFileID: Self.ino(url), toTrash: true)
        if case .removed = r {} else { Issue.record("\(r)") }
        #expect(!exists(url))
    }

    @Test func changedItemNotTouched() throws {
        let fx = try ScanFixture()
        try fx.dir("x"); try fx.file("x/eski.bin", bytes: 100_000)
        let url = fx.root.appendingPathComponent("x"), old = Self.ino(url)
        try FileManager.default.removeItem(at: url)
        try fx.dir("x"); try fx.file("x/yeni.bin", bytes: 100_000)
        #expect(FileRemover.remove(url, expectedFileID: old, toTrash: false) == .changed)
        #expect(exists(url.appendingPathComponent("yeni.bin")))
        #expect(FileRemover.remove(fx.root.appendingPathComponent("yok"), expectedFileID: 1, toTrash: false) == .changed)
    }

    @Test func symlinkRemovesLinkOnly() throws {
        let fx = try ScanFixture(), target = try ScanFixture()
        try target.file("değerli.bin", bytes: 100_000)
        let link = fx.root.appendingPathComponent("bağ")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target.root)
        let r = FileRemover.remove(link, expectedFileID: Self.ino(link), toTrash: false)
        if case .removed = r {} else { Issue.record("\(r)") }
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == nil)
        #expect(exists(target.root.appendingPathComponent("değerli.bin")))
    }

    @Test func partialFailureReportsFreed() throws {
        let fx = try ScanFixture()
        try fx.dir("p/kilitli"); try fx.file("p/a.bin", bytes: 2_000_000); try fx.file("p/kilitli/b.bin", bytes: 1_000_000)
        let url = fx.root.appendingPathComponent("p"), locked = url.appendingPathComponent("kilitli")
        let before = try ScanFixture.du(url.path)
        #expect(chmod(locked.path, 0o555) == 0)
        defer { chmod(locked.path, 0o755) }
        let r = FileRemover.remove(url, expectedFileID: Self.ino(url), toTrash: false)
        guard case .failed(_, let freed) = r else { Issue.record("\(r)"); return }
        let after = try ScanFixture.du(url.path)
        #expect(abs(Double(freed - (before - after))) <= Double(before) * 0.01)
        #expect(exists(locked.appendingPathComponent("b.bin")))
    }
}
