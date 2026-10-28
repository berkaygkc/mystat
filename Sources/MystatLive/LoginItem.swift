import Foundation
import ServiceManagement

/// Oturum açılışında başlama (spec §2): ilk açılışta bir kez kaydolunur. Reddedilirse ya da kullanıcı sonradan
/// Giriş Öğeleri'nden kaldırırsa sessizce geçilir; bildirim gösterilmez.
public enum LoginItem {
    static let askedKey = "mystat.loginItem.asked"

    @discardableResult
    public static func ensureRegistered(defaults: UserDefaults = .standard) -> SMAppService.Status {
        let app = SMAppService.mainApp
        guard isInstalled(Bundle.main.bundleURL) else { return app.status }
        if shouldRegister(status: app.status, alreadyAsked: defaults.bool(forKey: askedKey)) {
            try? app.register()
            defaults.set(true, forKey: askedKey)
        }
        return app.status
    }

    /// Hiç kaydolmamış uygulamada macOS `.notRegistered` yerine `.notFound` da döndürebilir.
    static func shouldRegister(status: SMAppService.Status, alreadyAsked: Bool) -> Bool {
        (status == .notRegistered || status == .notFound) && !alreadyAsked
    }

    /// `~/Applications` ya da `/Applications` altındaki paket; giriş öğesinin yolu sabit kalır.
    static func isInstalled(_ bundle: URL) -> Bool {
        bundle.pathExtension == "app" && bundle.deletingLastPathComponent().lastPathComponent == "Applications"
    }
}
