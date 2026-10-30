import Darwin
import Foundation
import MystatCore
import Synchronization
import Testing
@testable import MystatProbes

/// Fixtures in a temporary folder: each test creates and deletes its own root.
final class ScanFixture {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mystat-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    func dir(_ rel: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(rel), withIntermediateDirectories: true)
    }
    func file(_ rel: String, bytes: Int) throws {
        var d = Data(count: bytes)
        d.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, bytes) }   // incompressible content
        try d.write(to: root.appendingPathComponent(rel))
    }
    /// `du -sk` × 1024.
    static func du(_ path: String) throws -> Int64 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/du"); p.arguments = ["-sk", path]
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return Int64(s.split(separator: "\t").first.flatMap { Int64($0) } ?? -1) * 1024
    }
}

final class ProgressLog: Sendable {
    let last = Mutex<DirectoryScanner.Progress?>(nil)
    let calls = Atomic<Int>(0)
}

@Suite struct DirectoryScannerTests {
    static let MB = 1_000_000

    func scan(_ root: URL, workers: Int = 4) -> (ScanIndex, ProgressLog) {
        let log = ProgressLog()
        let idx = DirectoryScanner(root: root.path, workers: workers).scan(
            onProgress: { p in log.last.withLock { $0 = p }; log.calls.add(1, ordering: .relaxed) },
            isCancelled: { false })
        return (idx, log)
    }

    @Test func sizesAndStructure() throws {
        let fx = try ScanFixture()
        try fx.dir("a/b"); try fx.dir("c")
        try fx.file("a/küçük.bin", bytes: 1 * Self.MB)
        try fx.file("a/büyük.bin", bytes: 12 * Self.MB)
        for i in 1...3 { try fx.file("a/b/\(i).txt", bytes: 100_000) }
        let (idx, log) = scan(fx.root)
        let t = idx.totals()
        let du = try ScanFixture.du(fx.root.path)
        #expect(abs(Double(t[0] - du)) <= Double(du) * 0.01, "tarama \(t[0]) du \(du)")

        let top = idx.children(of: 0, totals: t)
        #expect(top.map(\.name) == ["a"])   // c is empty: not in the list
        guard case .dir(let a)? = top.first?.ref else { Issue.record("a klasör değil"); return }
        let kids = idx.children(of: a, totals: t)
        #expect(kids.map(\.name) == ["büyük.bin", "b", "Diğer"])
        if case .file? = kids.first?.ref {} else { Issue.record("büyük dosya ayrı değil") }
        #expect(kids.last?.ref == .other(count: 1))
        guard kids.count == 3, case .dir(let b) = kids[1].ref else { Issue.record("b klasör değil"); return }
        #expect(idx.children(of: b, totals: t).map(\.ref) == [.other(count: 3)])
        #expect(idx.dirCount == 4)
        #expect(log.last.withLock { $0?.bytes } == t[0])   // the last progress report gives the total
        #expect(log.last.withLock { $0?.dirs } == 4)
    }

    @Test func hardlinkCountedOnce() throws {
        let fx = try ScanFixture()
        try fx.dir("x"); try fx.dir("y")
        try fx.file("x/veri.bin", bytes: 12 * Self.MB)
        #expect(link(fx.root.appendingPathComponent("x/veri.bin").path, fx.root.appendingPathComponent("y/bağ.bin").path) == 0)
        let (idx, _) = scan(fx.root)
        let total = idx.totals()[0]
        #expect(total >= Int64(12 * Self.MB) && total < Int64(13 * Self.MB))
    }

    @Test func symlinkNotFollowed() throws {
        let fx = try ScanFixture(), target = try ScanFixture()
        try target.file("büyük.bin", bytes: 12 * Self.MB)
        try FileManager.default.createSymbolicLink(at: fx.root.appendingPathComponent("bağ"), withDestinationURL: target.root)
        let (idx, _) = scan(fx.root)
        #expect(idx.totals()[0] == 0)
        #expect(idx.dirCount == 1)
    }

    @Test func unreadableDirCounted() throws {
        let fx = try ScanFixture()
        try fx.dir("kapalı"); try fx.file("kapalı/gizli.bin", bytes: 12 * Self.MB)
        let locked = fx.root.appendingPathComponent("kapalı").path
        #expect(chmod(locked, 0) == 0)
        defer { chmod(locked, 0o755) }
        let (idx, _) = scan(fx.root)
        #expect(idx.inaccessible == 1)
        #expect(idx.totals()[0] == 0)
    }

    @Test func cancelStopsQuickly() throws {
        let fx = try ScanFixture()
        for i in 0..<20 { for j in 0..<100 { try fx.dir("d\(i)/e\(j)") } }
        let checks = Atomic<Int>(0)
        let t0 = Date()
        let idx = DirectoryScanner(root: fx.root.path).scan(
            onProgress: { _ in }, isCancelled: { checks.add(1, ordering: .relaxed).newValue > 20 })
        #expect(Date().timeIntervalSince(t0) < 0.5)
        #expect(idx.dirCount < 1000)   // not all 2,021 folders were listed
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MYSTAT_HOME_SCAN"] != nil))
    func liveHomeSmoke() throws {
        let home = NSHomeDirectory()
        let t0 = Date()
        let idx = DirectoryScanner(root: home).scan(onProgress: { _ in }, isCancelled: { false })
        let dt = Date().timeIntervalSince(t0)
        let total = idx.totals()[0], du = try ScanFixture.du(home)
        print("ev: \(Double(total) / 1e9) GB, du \(Double(du) / 1e9) GB, \(idx.dirCount) klasör, \(idx.inaccessible) erişilemeyen, \(dt) sn")
        #expect(abs(Double(total - du)) <= Double(du) * 0.02)
    }

    /// Folders that could trigger a TCC prompt are not opened without Full Disk Access; they count as unreadable.
    @Test func skippedFoldersAreNotOpened() throws {
        let fx = try ScanFixture()
        try fx.dir("Documents"); try fx.file("Documents/a.bin", bytes: 12 * Self.MB)
        try fx.dir("x/Fotoğraflar.photoslibrary"); try fx.file("x/Fotoğraflar.photoslibrary/b.bin", bytes: 12 * Self.MB)
        try fx.dir("y"); try fx.file("y/c.bin", bytes: 12 * Self.MB)
        let idx = DirectoryScanner(root: fx.root.path, skip: { DiskAccess.promptsWithoutAccess($0) })
            .scan(onProgress: { _ in }, isCancelled: { false })
        let t = idx.totals()
        #expect(idx.children(of: 0, totals: t).map(\.name) == ["y"])
        #expect(idx.inaccessible == 2)
    }
}
