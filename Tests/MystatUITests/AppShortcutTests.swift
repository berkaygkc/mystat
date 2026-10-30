import AppKit
import MystatTestSupport
import Testing
@testable import MystatUI

/// Shortcuts are not left to the main menu: while the panel is open the app may not process the main menu, and ⌘Q must work there too.
@Suite(.language("tr")) struct AppShortcutTests {
    @Test func standardShortcuts() {
        #expect(AppShortcut.match(chars: "q", modifiers: .command) == .quit)
        #expect(AppShortcut.match(chars: "w", modifiers: .command) == .closeWindow)
        #expect(AppShortcut.match(chars: "m", modifiers: .command) == .openMonitor)
    }
    @Test func otherCombinationsAreLeftAlone() {
        #expect(AppShortcut.match(chars: "q", modifiers: []) == nil)
        #expect(AppShortcut.match(chars: "q", modifiers: [.command, .option]) == nil)
        #expect(AppShortcut.match(chars: "Q", modifiers: [.command, .shift]) == nil)
        #expect(AppShortcut.match(chars: nil, modifiers: .command) == nil)
    }
}
