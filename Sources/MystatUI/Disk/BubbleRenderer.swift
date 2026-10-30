import AppKit
import Metal
import MetalKit
import MystatCore
import QuartzCore

/// Draws the glass bubble shader: an `MTKView` delegate when live, an offscreen texture for snapshots.
@MainActor
final class BubbleRenderer: NSObject, MTKViewDelegate {
    static let pixelFormat = MTLPixelFormat.bgra8Unorm

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    /// Live frame: time on the renderer clock (s) → frame. Nothing is drawn if it returns `nil` (no size yet).
    var frameProvider: ((Double) -> BubbleFrame?)?
    var isDark = false
    /// Target of the light source (a point, from the top left); followed with 0.12 smoothing while drawing.
    /// `nil`: the pointer is outside the map and the light rests at the top left.
    var mouse: CGPoint?
    private var smoothed: CGPoint?
    private let start = CACurrentMediaTime()

    /// Shared clock of the engine and the shader.
    var now: Double { CACurrentMediaTime() - start }

    init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue(),
              let lib = try? device.makeLibrary(source: BubbleShaderSource.msl, options: nil),
              let vf = lib.makeFunction(name: "fullscreenVertex"), let ff = lib.makeFunction(name: "bubbleFragment")
        else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = vf
        d.fragmentFunction = ff
        d.colorAttachments[0].pixelFormat = Self.pixelFormat
        guard let p = try? device.makeRenderPipelineState(descriptor: d) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = p
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        // Don't tax the GPU when scrolled out of view.
        let t = now
        guard let provider = frameProvider, !view.visibleRect.isEmpty, view.bounds.width > 0, let f = provider(t),
              let rpd = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer() else { return }
        let px = view.drawableSize
        let scale = Double(px.width / view.bounds.width)
        let size = CGSize(width: px.width / scale, height: px.height / scale)
        let target = mouse ?? Self.outside(size)
        var m = smoothed ?? target
        m.x += (target.x - m.x) * 0.12
        m.y += (target.y - m.y) * 0.12
        smoothed = m
        let u = BubbleShaderSource.pack(f, size: size, scale: scale, time: t, dark: isDark, mouse: m)
        encode(u, pass: rpd, into: cb)
        // Presented within the CA transaction so it appears in the same frame as the (SwiftUI) labels.
        cb.commit()
        cb.waitUntilScheduled()
        drawable.present()
    }

    static func outside(_ size: CGSize) -> CGPoint { CGPoint(x: size.width * 0.22, y: -size.height * 0.15) }

    private func encode(_ u: [SIMD4<Float>], pass: MTLRenderPassDescriptor, into cb: MTLCommandBuffer) {
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        u.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Snapshot mode: draws the frame to an offscreen texture and returns an sRGB `CGImage`. `mouse` is used unsmoothed.
    func renderToImage(frame: BubbleFrame, size: CGSize, scale: CGFloat, time: Double) -> CGImage? {
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        guard w > 0, h > 0 else { return nil }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.pixelFormat, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: td), let cb = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        let s = CGSize(width: Double(w) / scale, height: Double(h) / scale)
        let u = BubbleShaderSource.pack(frame, size: s, scale: scale, time: time, dark: isDark, mouse: mouse ?? Self.outside(s))
        encode(u, pass: pass, into: cb)
        cb.commit()
        cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: cs,
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
