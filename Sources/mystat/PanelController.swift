import AppKit
import MystatCore
import MystatUI
import SwiftUI

/// Esc ve ⌘M alabilmesi için anahtar pencere olabilen, uygulamayı öne getirmeyen panel.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Paneli bloğun altında açar; dışarı tıklayınca, Esc'te ya da ikinci tıklamada kapanır.
@MainActor
final class PanelController {
    private var panel: KeyablePanel?
    private var outsideMonitor: Any?
    private var keyMonitor: Any?
    private let source: SampleSource
    private let openMonitor: (MonitorSection?, String?) -> Void
    var onVisibilityChange: ((Bool) -> Void)?

    init(source: SampleSource, openMonitor: @escaping (MonitorSection?, String?) -> Void) {
        self.source = source
        self.openMonitor = openMonitor
    }

    var isOpen: Bool { panel?.isVisible == true }

    func toggle(relativeTo button: NSStatusBarButton) {
        isOpen ? close() : open(relativeTo: button)
    }

    func open(relativeTo button: NSStatusBarButton) {
        let view = PanelView(source: source) { [weak self] section, group in
            self?.close()
            self?.openMonitor(section, group)
        }
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let p = KeyablePanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.contentView = host
        guard let anchor = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) else { return }
        let target = NSRect(x: anchor.maxX - size.width, y: anchor.minY - 6 - size.height, width: size.width, height: size.height)
        p.setFrame(target.offsetBy(dx: 0, dy: 6), display: false)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.1)
            p.animator().alphaValue = 1
            p.animator().setFrame(target, display: true)
        }
        panel = p
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.isOpen else { return e }
            if e.keyCode == 53 { self.close(); return nil }                                  // Esc
            if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "m" {     // ⌘M
                self.close(); self.openMonitor(nil, nil); return nil
            }
            return e
        }
        onVisibilityChange?(true)
    }

    func close() {
        guard let p = panel else { return }
        panel = nil
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 0 }
        Task { try? await Task.sleep(for: .milliseconds(160)); p.orderOut(nil) }
        onVisibilityChange?(false)
    }
}
