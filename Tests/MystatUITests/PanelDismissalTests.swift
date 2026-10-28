import AppKit
import Testing
@testable import MystatUI

/// Panel, kendi uygulamamızın başka bir penceresine (ör. monitör) tıklanınca da kapanmalı; panelin içi ve
/// durum öğesinin kendisi hariç (durum öğesi zaten aç/kapa yapar, iki kez kapanmasın).
@MainActor @Suite struct PanelDismissalTests {
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
    /// Pencere, çizilen gölge için panelden büyüktür; gölge payına tıklamak da "dışarısı" sayılır.
    @Test func clickInShadowMarginCloses() {
        let panel = window(), status = window()
        let content = CGRect(x: 74, y: 104, width: 352, height: 500)
        #expect(PanelDismissal.closes(clickWindow: panel, panel: panel, statusWindow: status, location: CGPoint(x: 20, y: 300), content: content))
        #expect(PanelDismissal.closes(clickWindow: panel, panel: panel, statusWindow: status, location: CGPoint(x: 200, y: 300), content: content) == false)
    }
}
