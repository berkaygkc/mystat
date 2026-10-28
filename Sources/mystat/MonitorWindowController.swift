import AppKit
import MystatCore
import MystatUI
import SwiftUI

/// Monitör penceresi: tam boy içerik, saydam başlık çubuğu, arkada bulanık masaüstü.
@MainActor
final class MonitorWindowController: NSObject, NSWindowDelegate {
    let state = MonitorState()
    private var window: NSWindow?
    private let source: SampleSource

    init(source: SampleSource) { self.source = source }

    func show(section: MonitorSection?, groupID: String?) {
        if let section { state.show(section, group: groupID) } else if let groupID { state.select(.cpu, groupID) }
        let w = window ?? makeWindow()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 1080, height: 680)
        w.backgroundColor = .clear
        let blur = NSVisualEffectView()
        blur.material = .underWindowBackground
        blur.blendingMode = .behindWindow
        blur.state = .active
        let host = NSHostingView(rootView: MonitorView(source: source, state: state))
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor), host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor), host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        w.contentView = blur
        w.center()
        w.delegate = self
        return w
    }
}
