import AppKit
import Testing
@testable import MystatUI

/// Menü çubuğu uygulamasında da ⌘Q ile çıkılabilmeli, ⌘W monitörü kapatmalı. ⌘M monitörü açar; küçültmeye bağlanmaz.
@MainActor @Suite struct AppMenuTests {
    func items(_ m: NSMenu) -> [NSMenuItem] { m.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) } }

    @Test func quitAndCloseHaveStandardShortcuts() {
        let all = items(AppMenu.make())
        let quit = all.first { $0.action == #selector(NSApplication.terminate(_:)) }
        #expect(quit?.keyEquivalent == "q" && quit?.keyEquivalentModifierMask == .command)
        let close = all.first { $0.action == #selector(NSWindow.performClose(_:)) }
        #expect(close?.keyEquivalent == "w")
        #expect(all.contains { $0.keyEquivalent == "m" } == false)
    }
}
