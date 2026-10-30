import Foundation
import MystatCore
import MystatTestSupport
import Testing
@testable import MystatLive

@MainActor @Suite(.language("tr")) struct DiskScanControllerTests {
    final class Clock { var now = Date(timeIntervalSince1970: 1_800_000_000) }

    /// Temporary root (a/: 12 MB + 1 MB, b/: 2 MB) and cache path.
    final class Fixture {
        let dir: URL, root: URL, cache: URL
        let clock = Clock()
        init() throws {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("mystat-ctl-\(UUID().uuidString)")
            root = dir.appendingPathComponent("ev"); cache = dir.appendingPathComponent("önbellek/diskscan.cache")
            for d in ["a", "b"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true) }
            try Self.write(root.appendingPathComponent("a/büyük.bin"), 12_000_000)
            try Self.write(root.appendingPathComponent("a/küçük.bin"), 1_000_000)
            try Self.write(root.appendingPathComponent("b/orta.bin"), 2_000_000)
        }
        deinit { try? FileManager.default.removeItem(at: dir) }
        static func write(_ url: URL, _ n: Int) throws {
            var d = Data(count: n); d.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, n) }
            try d.write(to: url)
        }
        @MainActor func controller() -> DiskScanController {
            DiskScanController(root: root.path, cacheURL: cache, now: { [clock] in clock.now }, usedBytes: { 100_000_000 })
        }
        var cacheExists: Bool { FileManager.default.fileExists(atPath: cache.path) }
    }

    @Test func scanProducesReadyTreeAndCache() async throws {
        let fx = try Fixture(), c = fx.controller()
        c.setVisible(true)
        c.start()
        if case .scanning = c.phase {} else { Issue.record("tarama başlamadı: \(c.phase)") }
        await c.waitUntilIdle()
        #expect(c.phase == .ready(scannedAt: fx.clock.now))
        #expect(c.tree.node(at: ["a"])?.children?.map(\.displayName) == ["büyük.bin", "Diğer"])
        #expect(c.tree.root.size > 0.0149 && c.tree.root.size < 0.0160)
        #expect(fx.cacheExists)
    }

    @Test func progressNeverReachesOneBeforeDone() {
        #expect(DiskScanController.progress(bytes: 50, estimate: 100) == 0.5)
        #expect(DiskScanController.progress(bytes: 200, estimate: 100) == 0.99)
        #expect(DiskScanController.progress(bytes: 10, estimate: 0) == 0)
        #expect(DiskScanController.shortPath("/Users/x/Library/Caches", root: "/Users/x") == "~/Library/Caches")
        #expect(DiskScanController.shortPath("/Users/x", root: "/Users/x") == "~")
    }

    @Test func cacheLoadsWithinHour() async throws {
        let fx = try Fixture(), c1 = fx.controller()
        let t0 = fx.clock.now
        c1.setVisible(true); c1.start(); await c1.waitUntilIdle()
        fx.clock.now = t0.addingTimeInterval(30 * 60)
        let c2 = fx.controller()
        #expect(c2.phase == .ready(scannedAt: t0))   // only the header is read at launch
        #expect(c2.tree.root.children == nil)
        c2.setVisible(true); await c2.waitUntilIdle()
        #expect(c2.tree.node(at: ["a"])?.children?.map(\.displayName) == ["büyük.bin", "Diğer"])
        #expect(abs(c2.tree.root.size - c1.tree.root.size) < 1e-9)
    }

    @Test func cacheExpiresAfterHour() async throws {
        let fx = try Fixture(), c1 = fx.controller()
        c1.setVisible(true); c1.start(); await c1.waitUntilIdle()
        fx.clock.now = fx.clock.now.addingTimeInterval(61 * 60)
        let c2 = fx.controller()
        #expect(c2.phase == .none)
        #expect(!fx.cacheExists)
        // In a session left open, the result is dropped once the time expires.
        c1.setVisible(true)
        #expect(c1.phase == .none); #expect(c1.tree.root.children == nil)
    }

    @Test func corruptCacheIgnored() async throws {
        let fx = try Fixture()
        try FileManager.default.createDirectory(at: fx.cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((0..<300).map { _ in UInt8.random(in: 0...255) }).write(to: fx.cache)
        let c = fx.controller()
        #expect(c.phase == .none)
        // A cache with an intact header but corrupt content: dropped when it cannot be loaded.
        let good = fx.controller(); good.setVisible(true); good.start(); await good.waitUntilIdle()
        var data = try Data(contentsOf: fx.cache)
        data.replaceSubrange(40..<data.count, with: Data(repeating: 7, count: data.count - 40))
        try data.write(to: fx.cache)
        let c2 = fx.controller()
        #expect(c2.phase != .none)
        c2.setVisible(true); await c2.waitUntilIdle()
        #expect(c2.phase == .none); #expect(!fx.cacheExists)
    }

    @Test func hiddenDropsTree() async throws {
        let fx = try Fixture(), c = fx.controller()
        c.setVisible(true); c.start(); await c.waitUntilIdle()
        #expect(c.tree.root.children != nil)
        let ready = c.phase
        c.setVisible(false)
        #expect(c.tree.root.children == nil)
        #expect(c.phase == ready)
        c.setVisible(true); await c.waitUntilIdle()
        #expect(c.tree.node(at: ["a"]) != nil)
    }

    @Test func cancelReturnsToPrevious() async throws {
        let fx = try Fixture(), c = fx.controller()
        c.setVisible(true)
        c.start(); c.cancel(); await c.waitUntilIdle()
        #expect(c.phase == .none); #expect(!fx.cacheExists)
        c.start(); await c.waitUntilIdle()
        let ready = c.phase
        fx.clock.now = fx.clock.now.addingTimeInterval(60)
        c.start(); c.cancel(); await c.waitUntilIdle()
        #expect(c.phase == ready)
        #expect(c.tree.node(at: ["a"])?.children?.isEmpty == false)
    }

    // MARK: Deletion

    @Test func controllerDeleteUpdatesTreeAndCache() async throws {
        let fx = try Fixture(), c = fx.controller()
        c.setVisible(true); c.start(); await c.waitUntilIdle()
        var basket = SelectionBasket()
        #expect(basket.toggle(["a", "büyük.bin"], in: c.tree) == .added)
        #expect(basket.toggle(["b"], in: c.tree) == .added)
        // b was deleted after the scan and recreated with the same name: left alone.
        let b = fx.root.appendingPathComponent("b")
        try FileManager.default.removeItem(at: b)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        try Fixture.write(b.appendingPathComponent("yeni.bin"), 1_000_000)

        let out = await c.delete(basket.items, mode: .permanent)
        #expect(out.changed == ["b"]); #expect(out.failed.isEmpty)
        #expect(abs(out.freedGB - 0.012) < 0.0005)
        #expect(c.tree.node(at: ["a", "büyük.bin"]) == nil)
        #expect(c.tree.node(at: ["b"]) != nil)
        #expect(!FileManager.default.fileExists(atPath: fx.root.appendingPathComponent("a/büyük.bin").path))
        #expect(FileManager.default.fileExists(atPath: b.appendingPathComponent("yeni.bin").path))

        let c2 = fx.controller(); c2.setVisible(true); await c2.waitUntilIdle()   // cache is current
        #expect(c2.tree.node(at: ["a", "büyük.bin"]) == nil)
        #expect(abs(c2.tree.root.size - c.tree.root.size) < 1e-9)
    }

    @Test func deleteRefusesProtectedAndOutside() async throws {
        let fx = try Fixture()
        try FileManager.default.createDirectory(at: fx.root.appendingPathComponent("Library/x"), withIntermediateDirectories: true)
        try Fixture.write(fx.root.appendingPathComponent("Library/x/veri.bin"), 1_000_000)
        let c = fx.controller()
        c.setVisible(true); c.start(); await c.waitUntilIdle()
        let lib = try #require(c.tree.node(at: ["Library"]))
        let out = await c.delete([BasketItem(path: ["Library"], name: "Library", size: lib.size, kind: .folder, fileID: lib.fileID),
                                  BasketItem(path: ["..", "ev"], name: "ev", size: 1, kind: .folder, fileID: 1)], mode: .permanent)
        #expect(out.freedGB == 0); #expect(out.failed == ["Library", "ev"])
        #expect(FileManager.default.fileExists(atPath: fx.root.appendingPathComponent("Library/x/veri.bin").path))
    }

    // MARK: Deletion and cache edge cases

    /// Even if the section changes while a deletion is running, deleted items drop out of the tree and the cache; they do not reappear on return.
    @Test func deleteWhileHiddenStillUpdatesTreeAndCache() async throws {
        let fx = try Fixture(), c = fx.controller()
        c.setVisible(true); c.start(); await c.waitUntilIdle()
        var basket = SelectionBasket()
        #expect(basket.toggle(["a", "büyük.bin"], in: c.tree) == .added)
        let items = basket.items
        let task = Task { await c.delete(items, mode: .permanent) }
        while !c.isDeleting { await Task.yield() }
        c.setVisible(false)
        let out = await task.value
        #expect(abs(out.freedGB - 0.012) < 0.0005)
        #expect(c.tree.root.children == nil)   // section closed: dropped when the deletion finished
        c.setVisible(true); await c.waitUntilIdle()
        #expect(c.tree.node(at: ["a"]) != nil)
        #expect(c.tree.node(at: ["a", "büyük.bin"]) == nil)
        let c2 = fx.controller(); c2.setVisible(true); await c2.waitUntilIdle()
        #expect(c2.tree.node(at: ["a", "büyük.bin"]) == nil)
    }

    /// A scan that is started and stopped while the cache is loading: it comes back with the previous result tree (no empty map is left).
    @Test func cancelledRescanDuringLoadRestoresTree() async throws {
        let fx = try Fixture(), c = fx.controller()
        c.setVisible(true); c.start(); await c.waitUntilIdle()
        let ready = c.phase
        c.setVisible(false); c.setVisible(true)   // loading started
        c.start(); c.cancel(); await c.waitUntilIdle()
        #expect(c.phase == ready)
        #expect(c.tree.node(at: ["a"])?.children?.isEmpty == false)
    }

    /// Folders that could trigger a permission prompt are not scanned without Full Disk Access.
    @Test func withoutFullDiskAccessPromptFoldersAreSkipped() async throws {
        let fx = try Fixture()
        try FileManager.default.createDirectory(at: fx.root.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        try Fixture.write(fx.root.appendingPathComponent("Documents/gizli.bin"), 12_000_000)
        for access in [false, true] {
            let c = DiskScanController(root: fx.root.path, cacheURL: fx.cache, now: { [clock = fx.clock] in clock.now },
                                       usedBytes: { 100_000_000 }, fullDiskAccess: { access })
            c.setVisible(true); c.start(); await c.waitUntilIdle()
            #expect((c.tree.node(at: ["Documents"]) != nil) == access)
            #expect((c.inaccessible > 0) == !access)
        }
    }
}
