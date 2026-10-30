import AppKit
import MystatTestSupport
import Testing
@testable import MystatUI

/// The panel must also close when another window of our own app (e.g. the monitor) is clicked; except for the panel's interior and
/// the status item itself (the status item already toggles the panel; it must not close twice).
@MainActor @Suite(.language("tr")) struct PanelDismissalTests {
    func window() -> NSWindow { NSWindow(contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless], backing: .buffered, defer: true) }

    @Test func clickInAnotherOwnWindowCloses() {
        let panel = window(), status = window(), monitor = window()
        #expect(PanelDismissal.closes(clickWindow: monitor, panel: panel, statusWindow: status))
        #expect(PanelDismissal.closes(clickWindow: nil, panel: panel, statusWindow: status))
    }

    @Test func clickInsidePanelOrOnStatusItemKeepsIt() {
        let panel = window(), status = window()
        #expect(PanelDismissal.closes(clickWindow: panel, panel: panel, statusWindow: status) == false)
        #expect(PanelDismissal.closes(clickWindow: status, panel: panel, statusWindow: status) == false)
    }
    /// The window is larger than the panel to fit the drawn shadow; clicking the shadow margin also counts as "outside".
    @Test func clickInShadowMarginCloses() {
        let panel = window(), status = window()
        let content = CGRect(x: 74, y: 104, width: 352, height: 500)
        #expect(PanelDismissal.closes(clickWindow: panel, panel: panel, statusWindow: status, location: CGPoint(x: 20, y: 300), content: content))
        #expect(PanelDismissal.closes(clickWindow: panel, panel: panel, statusWindow: status, location: CGPoint(x: 200, y: 300), content: content) == false)
    }
}
