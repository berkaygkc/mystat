import Foundation
import ServiceManagement

/// Launch at login: registers once on first launch. If denied, or if the user later removes it from
/// Login Items, it is skipped silently; no notification is shown.
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

    /// For an app that was never registered, macOS may return `.notFound` instead of `.notRegistered`.
    static func shouldRegister(status: SMAppService.Status, alreadyAsked: Bool) -> Bool {
        (status == .notRegistered || status == .notFound) && !alreadyAsked
    }

    /// The bundle under `~/Applications` or `/Applications`; keeps the login item's path stable.
    static func isInstalled(_ bundle: URL) -> Bool {
        bundle.pathExtension == "app" && bundle.deletingLastPathComponent().lastPathComponent == "Applications"
    }
}
