import AppKit
import MystatCore
import MystatTestSupport
import SwiftUI
import Testing
@testable import MystatUI

/// Olay sürerken nabız atan nokta SwiftUI'yi her karede güncelletmemeli: monitör penceresinde bu, bütün pencerenin
/// her karede yeniden yerleşmesi demekti (ölçüldü: olay varken %35–60 CPU, pencere görünmezken bile).
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
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))   // ilk yerleşim
        let start = host.layouts
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        #expect(host.layouts - start <= 3, "1,2 sn'de \(host.layouts - start) yerleşim")
    }
}
