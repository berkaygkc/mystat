import AppKit
import SwiftUI

/// Durum noktası; olayda nabız atar. Nabız Core Animation'da çalışır: SwiftUI'nin sonsuz animasyonu görünüm ağacını her
/// karede güncelletiyordu ve monitörde bu, bütün pencerenin her karede yeniden yerleşmesi demekti (olay varken %35–60
/// CPU, pencere görünmezken bile). Görünüş aynı: 0,8 sn'de saydamlık 1 → 0,45 ve ölçek 1 → 0,82, gidip gelerek.
struct PulseDot: NSViewRepresentable {
    let color: Color
    let pulsing: Bool

    final class DotView: NSView {
        private let dot = CALayer()
        var color = NSColor.clear { didSet { needsDisplay = true } }
        var pulsing = false { didSet { if pulsing != oldValue { updatePulse() } } }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.addSublayer(dot)
        }
        required init?(coder: NSCoder) { nil }

        override var wantsUpdateLayer: Bool { true }
        override func updateLayer() {
            effectiveAppearance.performAsCurrentDrawingAppearance { dot.backgroundColor = color.cgColor }
        }

        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            dot.bounds = CGRect(origin: .zero, size: bounds.size)   // dönüşümlü katmanda frame tanımsız
            dot.position = CGPoint(x: bounds.midX, y: bounds.midY)
            dot.cornerRadius = min(bounds.width, bounds.height) / 2
            CATransaction.commit()
        }

        /// Pencereden çıkıp girince (panel yeniden açılınca) animasyon yeniden eklenir.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updatePulse()
        }

        /// Durağan değer soluk hal: durağan çizimde (görüntü modu) eski SwiftUI noktasıyla aynı görünür; canlıda animasyon
        /// bunun üzerinde 1 ile 0,45 arasında gidip gelir.
        private func updatePulse() {
            dot.removeAnimation(forKey: "pulse")
            CATransaction.begin(); CATransaction.setDisableActions(true)
            dot.opacity = pulsing ? 0.45 : 1
            dot.transform = pulsing ? CATransform3DMakeScale(0.82, 0.82, 1) : CATransform3DIdentity
            CATransaction.commit()
            guard pulsing, window != nil else { return }
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 1; opacity.toValue = 0.45
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1; scale.toValue = 0.82
            let pulse = CAAnimationGroup()
            pulse.animations = [opacity, scale]
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.add(pulse, forKey: "pulse")
        }
    }

    func makeNSView(context: Context) -> DotView { DotView() }

    func updateNSView(_ v: DotView, context: Context) {
        let c = NSColor(color)
        if v.color != c { v.color = c }
        v.pulsing = pulsing
    }
}
