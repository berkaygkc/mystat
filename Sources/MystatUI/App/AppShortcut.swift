import AppKit

/// Uygulama kısayolları. Ana menüye bırakılmaz: panel açıkken uygulama menü kısayollarını işlemeyebilir.
/// Yerel tuş izleyicisi her tuşu görür; eşleme burada.
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
