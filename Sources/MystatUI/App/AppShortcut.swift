import AppKit

/// App shortcuts. They are not left to the main menu: while the panel is open the app may not process menu shortcuts.
/// The local key monitor sees every key; the mapping lives here.
public enum AppShortcut: Equatable, Sendable {
    case quit, closeWindow, openMonitor

    public static func match(chars: String?, modifiers: NSEvent.ModifierFlags) -> AppShortcut? {
        guard modifiers.intersection([.command, .option, .control, .shift]) == .command else { return nil }
        switch chars {
        case "q": return .quit
        case "w": return .closeWindow
        case "m": return .openMonitor
        default: return nil
        }
    }
}
