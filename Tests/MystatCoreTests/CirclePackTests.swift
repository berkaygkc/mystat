import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

@Suite(.language("tr")) struct CirclePackTests {
    @Test func siblingsDoNotOverlap() {
        let c = CirclePack.packSiblings([50, 40, 30, 20, 10, 5])
        for i in c.indices { for j in c.indices where j > i { #expect(hypot(c[i].x - c[j].x, c[i].y - c[j].y) >= c[i].r + c[j].r - 1e-6) } }
    }
    @Test func layoutFitsRoot() {
        let out = CirclePack.layout(children: [96, 52, 46.7, 18, 9, 6, 4.2, 3.1].map { PackInput(value: $0) }, size: 508, rootPadding: 13, childPadding: 4)
        for (c, _) in out { #expect(hypot(c.x - 254, c.y - 254) + c.r <= 254 + 1e-6) }
        #expect(out[0].0.r > out[1].0.r)
    }
    @Test func singleChildCentered() {
        let out = CirclePack.layout(children: [PackInput(value: 10)], size: 200, rootPadding: 13, childPadding: 4)
        // d3's two-pass padding does not give exactly 13 pt; the value was verified against d3.
        #expect(abs(out[0].0.x - 100) < 1e-6); #expect(abs(out[0].0.r - 88.49557522123894) < 1e-9)
    }
    /// Values were computed with d3-hierarchy 3.1.2 (same input, size 508, padding 13/4).
    @Test func matchesD3() {
        let input = [PackInput(value: 96, grandchildren: [41, 28, 14, 9, 4]), PackInput(value: 52, grandchildren: [31, 12, 9]),
                     PackInput(value: 46.7), PackInput(value: 18, grandchildren: [9.5, 5.2, 3.3]),
                     PackInput(value: 9), PackInput(value: 6), PackInput(value: 4.2), PackInput(value: 3.1)]
        let out = CirclePack.layout(children: input, size: 508, rootPadding: 13, childPadding: 4)
        let ref: [(Double, Double, Double)] = [(144.178, 254, 132.6172), (392.3976, 254, 104.0416), (291.8035, 415.1611, 74.3768),
                                               (290.5938, 106.1964, 63.8688), (185.2544, 82.0078, 32.6513), (179.367, 421.1743, 26.6596),
                                               (387.8184, 116.1686, 22.3051), (393.534, 388.7604, 19.1628)]
        for (i, r) in ref.enumerated() {
            #expect(abs(out[i].0.x - r.0) < 0.01 && abs(out[i].0.y - r.1) < 0.01 && abs(out[i].0.r - r.2) < 0.01, "çocuk \(i)")
        }
        let lib: [(Double, Double, Double)] = [(84.808, 254, 69.69), (215.6466, 254, 57.5914), (160.2068, 339.4652, 40.7233),
                                               (159.4603, 178.89, 32.6513), (104.3109, 161.0084, 21.7675)]
        for (i, r) in lib.enumerated() {
            #expect(abs(out[0].1[i].x - r.0) < 0.01 && abs(out[0].1[i].y - r.1) < 0.01 && abs(out[0].1[i].r - r.2) < 0.01, "torun \(i)")
        }
    }
    /// The front chain is circular; if it is not broken when packing ends, every layout leaks its nodes and circles
    /// (layout runs on every frame while the window is being resized).
    @Test func packingReleasesItsFrontChain() {
        weak var probe: CirclePack.Circ?
        do {
            let circles = (1...12).map { CirclePack.Circ(r: Double($0)) }
            probe = circles[5]
            var random = CirclePack.LCG()
            _ = CirclePack.packSiblingsRandom(circles, &random)
        }
        #expect(probe == nil)
    }
}
