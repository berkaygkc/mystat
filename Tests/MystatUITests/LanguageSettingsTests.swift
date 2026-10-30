import Foundation
import MystatCore
import MystatTestSupport
import Testing
@testable import MystatUI

@MainActor @Suite(.language("en")) struct LanguageSettingsTests {
    static func defaults() -> UserDefaults { UserDefaults(suiteName: "mystat-test-\(UUID().uuidString)")! }

    @Test func firstLaunchDetects() {
        var applied: [String] = []
        let tr = LanguageSettings(defaults: Self.defaults(), preferred: ["tr-TR", "en-US"]) { applied.append($0) }
        #expect(tr.choice == nil); #expect(tr.code == "tr"); #expect(applied == ["tr"])
        #expect(LanguageSettings(defaults: Self.defaults(), preferred: ["fr"]) { _ in }.code == "en")
    }

    @Test func choicePersistsAndWins() {
        let d = Self.defaults()
        var applied: [String] = []
        let s = LanguageSettings(defaults: d, preferred: ["tr-TR"]) { applied.append($0) }
        s.select("en")
        #expect(s.code == "en"); #expect(s.choice == "en"); #expect(applied.last == "en")
        #expect(d.string(forKey: LanguageSettings.key) == "en")
        #expect(LanguageSettings(defaults: d, preferred: ["tr-TR"]) { _ in }.code == "en")   // also on a fresh launch
        s.select(nil)
        #expect(s.code == "tr"); #expect(s.choice == nil); #expect(d.string(forKey: LanguageSettings.key) == nil)
    }

    @Test func unknownStoredChoiceFallsBack() {
        let d = Self.defaults(); d.set("xx", forKey: LanguageSettings.key)
        let s = LanguageSettings(defaults: d, preferred: ["tr"]) { _ in }
        #expect(s.choice == nil); #expect(s.code == "tr")
    }

    @Test func notifiesOnChange() {
        let s = LanguageSettings(defaults: Self.defaults(), preferred: ["en"]) { _ in }
        var calls = 0
        s.onChange = { calls += 1 }
        s.select("tr"); s.select("tr")   // selecting the same language a second time does not notify
        #expect(calls == 1)
        #expect(s.menuItems.map(\.title) == ["System (English)", "English", "Türkçe"])
    }
}
