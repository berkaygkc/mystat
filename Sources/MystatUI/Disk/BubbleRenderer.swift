import AppKit
import Metal
import MetalKit
import MystatCore
import QuartzCore

/// Cam balon shader'ını çizer: canlıda `MTKView` temsilcisi, anlık görüntüde ekran dışı doku.
@MainActor
final class BubbleRenderer: NSObject, MTKViewDelegate {
    static let pixelFormat = MTLPixelFormat.bgra8Unorm

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    /// Canlı kare: renderer saatindeki zaman (sn) → kare. `nil` dönerse (boyut henüz yok) çizilmez.
    var frameProvider: ((Double) -> BubbleFrame?)?
    var isDark = false
    /// Işık kaynağının hedefi (nokta, sol üstten); çizimde 0,12 yumuşatmayla izlenir (mockup `mouse`←`mt`).
    /// `nil`: imleç harita dışında, ışık sol üst dışında durur (mockup `mouseleave`).
    var mouse: CGPoint?
    private var smoothed: CGPoint?
    private let start = CACurrentMediaTime()

    /// Motorun ve shader'ın ortak saati.
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
        // Kaydırılıp görünmez olduysa GPU'yu yorma.
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
        // Etiketler (SwiftUI) ile aynı karede görünsün diye CA işlemiyle sunulur.
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

    /// Anlık görüntü modu: kareyi ekran dışı dokuya çizip sRGB `CGImage` döndürür. `mouse` yumuşatılmadan kullanılır.
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
