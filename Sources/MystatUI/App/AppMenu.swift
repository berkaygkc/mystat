import AppKit

/// Görünmeyen ana menü: menü çubuğu uygulamasında yalnızca kısayollar için (⌘Q çık, ⌘W pencereyi kapat).
/// ⌘M bilerek yok: uygulama düzeyinde monitörü açar.
public enum AppMenu {
    @MainActor
    public static func make() -> NSMenu {
        let main = NSMenu()
        let app = NSMenuItem()
        app.submenu = NSMenu(title: "mystat")
        app.submenu?.addItem(withTitle: "mystat'tan çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(app)
        let window = NSMenuItem()
        window.submenu = NSMenu(title: "Pencere")
        window.submenu?.addItem(withTitle: "Kapat", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(window)
        return main
    }
}
