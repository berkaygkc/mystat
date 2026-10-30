import AppKit
import MystatCore
import MystatTestSupport
import SwiftUI
import Testing
@testable import MystatUI

/// A dot that pulses during an incident must not make SwiftUI update every frame: in the monitor window that meant the whole window
/// re-laid out every frame (measured: 35-60% CPU during an incident, even while the window was not visible).
@MainActor @Suite(.language("tr")) struct KickerPulseTests {
    final class CountingHost<V: View>: NSHostingView<V> {
        var layouts = 0
        override func layout() { layouts += 1; super.layout() }
    }

    @Test func pulseDoesNotDriveLayout() {
        let host = CountingHost(rootView: Kicker("OLAY · 4 DK", level: .crit, pulsing: true).padding(20))
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.orderFrontRegardless()
        defer { win.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))   // first layout
        let start = host.layouts
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        #expect(host.layouts - start <= 3, "1,2 sn'de \(host.layouts - start) yerleşim")
    }
}
