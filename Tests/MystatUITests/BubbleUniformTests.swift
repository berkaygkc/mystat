import CoreGraphics
import MystatCore
import MystatTestSupport
import Testing
@testable import MystatUI

/// The shader buffer must be filled in the layout the Metal shader expects, in device pixels.
@MainActor @Suite(.language("tr")) struct BubbleUniformTests {
    let size = CGSize(width: 655, height: 560)

    func close(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Bool { (0..<4).allSatisfy { abs(a[$0] - b[$0]) < 1e-3 } }

    func restFrame() -> BubbleFrame {
        let e = BubbleEngine(tree: SampleSource(seed: 1).diskTree, path: [], viewSize: size)
        return e.frame(at: 2, hover: nil, selection: { $0 == ["Library"] ? .selected : .none })
    }

    @Test func packsHeaderInDevicePixels() {
        let f = restFrame()
        let u = BubbleShaderSource.pack(f, size: size, scale: 2, time: 2, dark: true, mouse: CGPoint(x: 180, y: 60))
        #expect(u.count == BubbleShaderSource.uniformVectorCount)
        #expect(close(u[0], SIMD4(1310, 1120, 2, 2)))
        #expect(close(u[1], SIMD4(1, Float(f.zoomLog), 360, 120)))
        #expect(close(u[2], SIMD4(Float(min(24, f.mains.count)), Float(min(96, f.droplets.count)), 0, 0)))
    }

    @Test func packsBubblesWithKindColourAndSelection() {
        let f = restFrame()
        let u = BubbleShaderSource.pack(f, size: size, scale: 2, time: 2, dark: false, mouse: .zero)
        let m = f.mains[0]
        #expect(m.item.name == "Library")
        #expect(close(u[8], SIMD4(Float(m.x * 2), Float(m.y * 2), Float(m.r * 2), 1)))
        #expect(close(u[32], SIMD4(Float(m.item.phase), Float(m.amp), Float(m.alpha), Float(m.hover))))
        #expect(close(u[56], SIMD4(0.404, 0.392, 0.961, 0)))      // folder purple
        let d = f.droplets[0]
        #expect(close(u[80], SIMD4(Float(d.x * 2), Float(d.y * 2), Float(d.r * 2), Float(d.alpha))))
        #expect(u[3] == .zero)   // no membrane
        #expect(u[6] == .zero)   // no ripple
        #expect(u[7] == .zero)   // no background tint at the root
    }

    @Test func blendsBackgroundTintTowardsEnteredKind() {
        let e = BubbleEngine(tree: SampleSource(seed: 1).diskTree, path: [], viewSize: size)
        _ = e.frame(at: 2, hover: nil, selection: { _ in .none })
        #expect(e.zoomIn("Library", at: 2))
        let f = e.frame(at: 2.7, hover: nil, selection: { _ in .none })
        let u = BubbleShaderSource.pack(f, size: size, scale: 1, time: 2.7, dark: false, mouse: .zero)
        let k = Float(f.bgT)
        #expect(k > 0 && k < 1)
        #expect(close(u[7], SIMD4(0.404 * k, 0.392 * k, 0.961 * k, k)))
        #expect(u[3].z > 0)                                       // membrane radius
        #expect(close(u[5], SIMD4(0.404, 0.392, 0.961, 0)))       // membrane color
    }
}
