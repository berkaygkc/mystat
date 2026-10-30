import Foundation
import MystatCore
import Observation

/// The app language: the user's choice (persisted), else the first supported language among the Mac's preferred languages, else English.
@MainActor @Observable
public final class LanguageSettings {
    public static let key = "mystat.language"
    /// The app's settings instance (set up at launch). Absent in render mode and in tests: root views do not observe language changes.
    public static var current: LanguageSettings?

    /// The user's choice; nil = system language.
    public private(set) var choice: String?
    /// The active language.
    public private(set) var code: String
    /// Called when the language changes (menu bar, panel height, measurement strings).
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

    /// The language detected from the system settings.
    public var detected: String { L10n.detect(preferred: preferred, available: localizer.languages.map(\.code)) }

    /// `nil`: return to the system language. An unknown code also returns to the system language.
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

    /// "System (English)", followed by the languages under their own names.
    public var menuItems: [MenuItem] {
        let detectedName = localizer.languages.first { $0.code == detected }?.name ?? "English"
        return [MenuItem(choice: nil, title: L10n.t("language.system", ["name": detectedName]))]
            + localizer.languages.map { MenuItem(choice: $0.code, title: $0.name) }
    }
}
