import Foundation
import MystatCore
import Observation

/// Uygulamanın dili: kullanıcının seçimi (kalıcı) ya da Mac'in tercih ettiği dillerden desteklenen ilki, yoksa İngilizce.
@MainActor @Observable
public final class LanguageSettings {
    public static let key = "mystat.language"
    /// Uygulamanın ayarı (açılışta kurulur). Görüntü modu ve testlerde yok: kök görünümler dil değişimini izlemez.
    public static var current: LanguageSettings?

    /// Kullanıcının seçimi; nil = sistem dili.
    public private(set) var choice: String?
    /// Etkin dil.
    public private(set) var code: String
    /// Dil değişince (menü çubuğu, panel boyu, ölçüm metinleri).
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let preferred: [String]
    @ObservationIgnored private let localizer: Localizer
    @ObservationIgnored private let apply: (String) -> Void

    public init(defaults: UserDefaults = .standard, preferred: [String] = Locale.preferredLanguages, localizer: Localizer = .shared,
                apply: @escaping (String) -> Void = { L10n.setLanguage($0) }) {
        self.defaults = defaults; self.preferred = preferred; self.localizer = localizer; self.apply = apply
        let codes = localizer.languages.map(\.code)
        let stored = defaults.string(forKey: Self.key).flatMap { codes.contains($0) ? $0 : nil }
        choice = stored
        code = stored ?? L10n.detect(preferred: preferred, available: codes)
        apply(code)
    }

    public var languages: [Language] { localizer.languages }

    /// Sistem dili tespit edilen dil.
    public var detected: String { L10n.detect(preferred: preferred, available: localizer.languages.map(\.code)) }

    /// `nil`: sistem diline dön. Bilinmeyen kod sistem diline döner.
    public func select(_ newChoice: String?) {
        let valid = newChoice.flatMap { c in localizer.languages.contains { $0.code == c } ? c : nil }
        if let valid { defaults.set(valid, forKey: Self.key) } else { defaults.removeObject(forKey: Self.key) }
        let newCode = valid ?? detected
        let changed = newCode != code
        choice = valid
        code = newCode
        guard changed else { return }
        apply(newCode)
        onChange?()
    }

    public struct MenuItem: Identifiable, Equatable {
        public let choice: String?
        public let title: String
        public var id: String { choice ?? "" }
    }

    /// "System (English)", ardından diller kendi adlarıyla.
    public var menuItems: [MenuItem] {
        let detectedName = localizer.languages.first { $0.code == detected }?.name ?? "English"
        return [MenuItem(choice: nil, title: L10n.t("language.system", ["name": detectedName]))]
            + localizer.languages.map { MenuItem(choice: $0.code, title: $0.name) }
    }
}
