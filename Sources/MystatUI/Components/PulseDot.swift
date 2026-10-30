import AppKit
import SwiftUI

/// Status dot; pulses during an incident. The pulse runs in Core Animation: SwiftUI's infinite animation made the view tree
/// update every frame, which in the monitor meant the whole window re-laid out every frame (35-60% CPU during an incident,
/// even while the window was not visible). Same look: over 0.8 s opacity goes 1 → 0.45 and scale 1 → 0.82, autoreversing.
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
            dot.bounds = CGRect(origin: .zero, size: bounds.size)   // frame is undefined on a transformed layer
            dot.position = CGPoint(x: bounds.midX, y: bounds.midY)
            dot.cornerRadius = min(bounds.width, bounds.height) / 2
            CATransaction.commit()
        }

        /// The animation is re-added when the view leaves and re-enters a window (e.g. the panel reopens).
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updatePulse()
        }

        /// The resting value is the muted state: in static drawing (render mode) it looks like the old SwiftUI dot; live, the animation
        /// oscillates between 1 and 0.45 on top of it.
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
