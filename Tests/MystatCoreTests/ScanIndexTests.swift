import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

@Suite(.language("tr")) struct ScanIndexTests {
    static let MB: Int64 = 1_000_000

    /// root → a(5) → a/b(7 + x 20 MB), root → c, root small files 3.
    static func sample() -> (ScanIndex, a: Int32, b: Int32, c: Int32) {
        let idx = ScanIndex(rootName: "~")
        let a = idx.addDirectory(parent: 0, name: "a", fileID: 1)
        idx.addFiles(dir: a, big: [], smallBytes: 5 * MB, smallCount: 1)
        let b = idx.addDirectory(parent: a, name: "b", fileID: 2)
        idx.addFiles(dir: b, big: [(name: "x", bytes: 20 * MB, fileID: 10)], smallBytes: 7 * MB, smallCount: 2)
        let c = idx.addDirectory(parent: 0, name: "c", fileID: 3)
        idx.addFiles(dir: 0, big: [], smallBytes: 3 * MB, smallCount: 1)
        return (idx, a, b, c)
    }

    @Test func totalsBottomUp() {
        let (idx, a, b, c) = Self.sample()
        let t = idx.totals()
        #expect(t[0] == 35 * Self.MB)
        #expect(t[a] == 32 * Self.MB)
        #expect(t[b] == 27 * Self.MB)
        #expect(t[c] == 0)
        #expect(idx.dirCount == 4)
    }

    @Test func childrenAllPlusSmallOther() {
        let idx = ScanIndex(rootName: "~")
        for i in 1...30 {
            let d = idx.addDirectory(parent: 0, name: "d\(i)", fileID: UInt64(i))
            idx.addFiles(dir: d, big: [], smallBytes: Int64(i) * Self.MB, smallCount: 1)
        }
        _ = idx.addDirectory(parent: 0, name: "boş", fileID: 99)   // 0 bytes: not in the list
        idx.addFiles(dir: 0, big: [], smallBytes: 4 * Self.MB, smallCount: 100)
        let kids = idx.children(of: 0, totals: idx.totals())
        #expect(kids.count == 31)
        #expect(kids.prefix(30).map(\.name) == (1...30).reversed().map { "d\($0)" })
        #expect(kids.prefix(30).map(\.bytes) == (1...30).reversed().map { Int64($0) * Self.MB })
        #expect(kids.last == ScanChild(name: "Diğer", bytes: 4 * Self.MB, ref: .other(count: 100)))
    }

    @Test func bigFilesAreChildren() {
        let (idx, _, b, _) = Self.sample()
        let kids = idx.children(of: b, totals: idx.totals())
        #expect(kids == [ScanChild(name: "x", bytes: 20 * Self.MB, ref: .file(fileID: 10)),
                         ScanChild(name: "Diğer", bytes: 7 * Self.MB, ref: .other(count: 2))])
    }

    @Test func pathOfDir() {
        let (idx, _, b, _) = Self.sample()
        #expect(idx.path(of: b) == ["a", "b"])
        #expect(idx.path(of: 0) == [])
    }

    @Test func encodeDecodeRoundTrip() throws {
        let (idx, a, b, c) = Self.sample()
        let data = idx.encoded()
        let d = try #require(ScanIndex(decoding: data))
        let t1 = idx.totals(), t2 = d.totals()
        for dir in [0, a, b, c] {
            #expect(t1[dir] == t2[dir])
            #expect(idx.children(of: dir, totals: t1) == d.children(of: dir, totals: t2))
        }
        #expect(d.path(of: b) == ["a", "b"])
        #expect(d.rootName == "~")

        #expect(ScanIndex(decoding: Data()) == nil)
        #expect(ScanIndex(decoding: Data((0..<200).map { _ in UInt8.random(in: 0...255) })) == nil)
        #expect(ScanIndex(decoding: data.prefix(data.count - 3)) == nil)
        var other = data; other[4] &+= 1   // version field
        #expect(ScanIndex(decoding: other) == nil)
    }

    @Test func liveTotalsWhileAdding() {
        let (idx, _, _, _) = Self.sample()
        let t1 = idx.totals()
        let d = idx.addDirectory(parent: 0, name: "d", fileID: 4)
        idx.addFiles(dir: d, big: [], smallBytes: 2 * Self.MB, smallCount: 1)
        let t2 = idx.totals()
        #expect(t2[0] == t1[0] + 2 * Self.MB)
        #expect(idx.children(of: 0, totals: t2).contains { $0.name == "d" })
    }

    @Test func largeIndexMemory() {
        let idx = ScanIndex(rootName: "~")
        for i in 1...600_000 {
            _ = idx.addDirectory(parent: Int32(i / 10), name: "klasör-\(i)", fileID: UInt64(i))
        }
        idx.finishAdding()
        #expect(idx.dirCount == 600_001)
        #expect(idx.storageBytes <= 40_000_000)
    }

    /// Items evicted to iCloud are not counted in size but their count is kept (for the deletion warning); it is summed up from subtrees.
    @Test func cloudOnlyItemsPropagate() throws {
        let (idx, a, b, _) = Self.sample()
        idx.addFiles(dir: b, big: [], smallBytes: 0, smallCount: 0, cloudCount: 3)
        idx.addFiles(dir: a, big: [], smallBytes: 0, smallCount: 0, cloudCount: 1)
        let t = idx.totals()
        #expect(t.cloud(0) == 4); #expect(t.cloud(a) == 4); #expect(t.cloud(b) == 3)
        #expect(idx.children(of: a, totals: t).first { $0.name == "b" }?.cloud == 3)
        #expect(idx.totals()[0] == 35 * Self.MB)   // not added to the size
        let d = try #require(ScanIndex(decoding: idx.encoded()))
        #expect(d.totals().cloud(0) == 4)
    }

    /// A cache with a valid structure but meaningless sizes (no LZFSE checksum) is not loaded; summing must not overflow and crash.
    @Test func implausibleSizesRejected() {
        let idx = ScanIndex(rootName: "~")
        for i in 1...3 {
            let d = idx.addDirectory(parent: 0, name: "d\(i)", fileID: UInt64(i))
            idx.addFiles(dir: d, big: [], smallBytes: Int64.max / 2, smallCount: 1)
        }
        #expect(ScanIndex(decoding: idx.encoded()) == nil)
    }
}
