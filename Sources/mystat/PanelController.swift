import AppKit
import MystatCore
import MystatUI
import SwiftUI

/// A panel that can become key window (to receive Esc and ⌘M) without bringing the app to the front.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Opens the panel below the block; closes on outside click, Esc or a second click.
/// While open the app is active (cursor, hover and ⌘Q only work that way); on close, focus returns to the previous app.
@MainActor
final class PanelController {
    private var panel: KeyablePanel?
    private var outsideMonitor: Any?
    private var insideMonitor: Any?
    private var keyMonitor: Any?
    private let source: any MetricsSource
    private let openMonitor: (MonitorSection?, String?) -> Void
    var onVisibilityChange: ((Bool) -> Void)?

    init(source: any MetricsSource, openMonitor: @escaping (MonitorSection?, String?) -> Void) {
        self.source = source
        self.openMonitor = openMonitor
    }

    var isOpen: Bool { panel?.isVisible == true }

    /// Shadow is drawn inside the window (the system shadow was drawn for the round panel relative to the square window): shadow margin.
    private static let margin = NSEdgeInsets(top: 44, left: 74, bottom: 104, right: 74)
    private var content = CGRect.zero

    func toggle(relativeTo button: NSStatusBarButton) {
        isOpen ? close() : open(relativeTo: button)
    }

    func open(relativeTo button: NSStatusBarButton) {
        removeMonitors()
        let m = Self.margin
        let view = SourceViews.panel(source: source) { [weak self] section, group in
            self?.close(returnFocus: false)
            self?.openMonitor(section, group)
        }
        .padding(EdgeInsets(top: m.top, leading: m.left, bottom: m.bottom, trailing: m.right))
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let cw = size.width - m.left - m.right, ch = size.height - m.top - m.bottom
        content = CGRect(x: m.left, y: m.bottom, width: cw, height: ch)   // window coordinates (from bottom left)
        let p = KeyablePanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false   // so AppKit does not hide it silently; closing always goes through close() (highlight and monitors)
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.contentView = host
        guard let anchor = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) else { return }
        let target = NSRect(x: anchor.maxX - cw - m.left, y: anchor.minY - 6 - ch - m.bottom, width: size.width, height: size.height)
        p.setFrame(target.offsetBy(dx: 0, dy: 6), display: false)
        p.alphaValue = 0
        NSApp.activate()
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.1)
            p.animator().alphaValue = 1
            p.animator().setFrame(target, display: true)
        }
        panel = p
        // Clicks on other apps arrive via the global monitor, clicks on our own windows (e.g. the monitor) via the local one.
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        let statusWindow = button.window
        insideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak p, weak statusWindow] e in
            guard let self else { return e }
            if PanelDismissal.closes(clickWindow: e.window, panel: p, statusWindow: statusWindow, location: e.locationInWindow, content: self.content) {
                self.close()
            }
            return e
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.isOpen else { return e }
            if e.keyCode == 53 { self.close(); return nil }                                  // Esc (⌘M is handled at the app level)
            return e
        }
        onVisibilityChange?(true)
    }

    /// Content size changed (language): resized so the window's top-right corner stays in place.
    func relayout() {
        Task { @MainActor [weak self] in
            await Task.yield()   // let SwiftUI draw in the new language
            guard let self, let p = self.panel, let host = p.contentView else { return }
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize, m = Self.margin
            guard size != p.frame.size else { return }
            self.content = CGRect(x: m.left, y: m.bottom, width: size.width - m.left - m.right, height: size.height - m.top - m.bottom)
            p.setFrame(NSRect(x: p.frame.maxX - size.width, y: p.frame.maxY - size.height, width: size.width, height: size.height), display: true)
        }
    }

    /// `returnFocus`: if the monitor will not be opened, focus returns to the previous app.
    func close(returnFocus: Bool = true) {
        guard let p = panel else { return }
        panel = nil
        removeMonitors()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 0 }
        Task { try? await Task.sleep(for: .milliseconds(160)); p.orderOut(nil) }
        onVisibilityChange?(false)
        if returnFocus, NSApp.isActive, !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { NSApp.deactivate() }
    }

    private func removeMonitors() {
        for m in [outsideMonitor, insideMonitor, keyMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(m) }
        outsideMonitor = nil; insideMonitor = nil; keyMonitor = nil
    }
}
