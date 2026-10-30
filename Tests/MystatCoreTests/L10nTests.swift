import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

@Suite struct L10nTests {
    /// Language files in a temporary folder: `[code: content]`.
    static func localizer(_ files: [String: String]) throws -> Localizer {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("l10n-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (code, body) in files { try body.write(to: dir.appendingPathComponent("\(code).json"), atomically: true, encoding: .utf8) }
        return Localizer(directory: dir)
    }

    static let en = #"{"_meta": {"name": "English", "locale": "en_US", "plural": "one"}, "a": "A", "only.en": "Only English", "used": "{used|poss3} used", "x": "{x} and {y}", "n.one": "{n} process", "n.other": "{n} processes"}"#
    static let tr = #"{"_meta": {"name": "Türkçe", "locale": "tr_TR", "plural": "none"}, "a": "A tr", "used": "{used|poss3} dolu", "gen": "{v|gen} yarısı", "n.other": "{n} süreç"}"#

    @Test func fallbackChain() throws {
        let l = try Self.localizer(["en": Self.en, "tr": Self.tr])
        #expect(L10n.t("a", language: "tr", localizer: l) == "A tr")
        #expect(L10n.t("only.en", language: "tr", localizer: l) == "Only English")
        #expect(L10n.t("missing.key", language: "tr", localizer: l) == "missing.key")
        #expect(L10n.t("a", language: "xx", localizer: l) == "A")
    }

    @Test func placeholdersAndModifiers() throws {
        let l = try Self.localizer(["en": Self.en, "tr": Self.tr])
        #expect(L10n.t("used", ["used": "12,7"], language: "tr", localizer: l) == "12,7'si dolu")
        #expect(L10n.t("used", ["used": "12,7"], language: "en", localizer: l) == "12,7 used")
        #expect(L10n.t("gen", ["v": "90"], language: "tr", localizer: l) == "90'ın yarısı")
        #expect(L10n.t("x", ["x": "1"], language: "en", localizer: l) == "1 and {y}")
    }

    @Test func pluralRules() throws {
        let l = try Self.localizer(["en": Self.en, "tr": Self.tr])
        #expect(L10n.plural("n", 1, language: "en", localizer: l) == "1 process")
        #expect(L10n.plural("n", 2, language: "en", localizer: l) == "2 processes")
        #expect(L10n.plural("n", 1, language: "tr", localizer: l) == "1 süreç")
        #expect(L10n.plural("n", 1_201, ["n": "1.201"], language: "tr", localizer: l) == "1.201 süreç")
        // In a language with a "one" rule, a missing .one falls back to .other.
        let l2 = try Self.localizer(["en": #"{"_meta": {"name": "English", "locale": "en_US"}, "k.other": "{n} things"}"#])
        #expect(L10n.plural("k", 1, language: "en", localizer: l2) == "1 things")
    }

    @Test func detectLanguage() {
        let available = ["en", "tr"]
        #expect(L10n.detect(preferred: ["tr-TR", "en-US"], available: available) == "tr")
        #expect(L10n.detect(preferred: ["fr-FR", "de"], available: available) == "en")
        #expect(L10n.detect(preferred: ["en-GB"], available: available) == "en")
        #expect(L10n.detect(preferred: ["pt-BR", "tr"], available: available) == "tr")
        #expect(L10n.detect(preferred: [], available: available) == "en")
        #expect(L10n.detect(preferred: ["pt-BR"], available: ["en", "pt-BR", "pt"]) == "pt-BR")
        // Script subtag: macOS reports "zh-Hans-CN"; it matches by trimming from the end.
        #expect(L10n.detect(preferred: ["zh-Hans-CN"], available: ["en", "zh-Hans"]) == "zh-Hans")
        #expect(L10n.detect(preferred: ["sr-Latn-RS"], available: ["en", "sr-Latn", "sr"]) == "sr-Latn")
        #expect(L10n.detect(preferred: ["pt-PT"], available: ["en", "pt-BR", "pt"]) == "pt")
    }

    /// A blank translation counts as missing: the English text shows, never an empty string on screen.
    @Test func emptyValueFallsBack() throws {
        let l = try Self.localizer(["en": Self.en, "tr": #"{"_meta": {"name": "Türkçe", "locale": "tr_TR", "plural": "none"}, "a": "", "n.other": ""}"#])
        #expect(L10n.t("a", language: "tr", localizer: l) == "A")
        #expect(L10n.plural("n", 3, language: "tr", localizer: l) == "3 processes")
    }

    @Test func brokenFileIgnored() throws {
        let l = try Self.localizer(["en": Self.en, "tr": Self.tr, "xx": "{ not json", "yy": #"{"a": "no meta"}"#])
        #expect(l.languages.map(\.code) == ["en", "tr"])
        #expect(l.languages.first?.name == "English")
        #expect(l.string("a", language: "xx") == nil)
    }

    @Test func overrideScopes() {
        L10n.$override.withValue("tr") { #expect(L10n.code == "tr") }
        L10n.$override.withValue("en") { #expect(L10n.code == "en") }
    }

    @Test(.language("tr")) func languageTraitScopes() async {
        #expect(L10n.code == "tr")
        await Task { #expect(L10n.code == "tr") }.value   // carries over into child tasks
    }

    /// Files in the bundle take precedence over the source tree; if the bundle is empty the source tree is used, and if neither exists the result is nil.
    @Test func locatePrefersBundle() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("loc-\(UUID().uuidString)")
        let bundle = tmp.appendingPathComponent("Resources"), source = tmp.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Locales"), withIntermediateDirectories: true)
        #expect(Localizer.locate(bundleResources: bundle, sourceRoot: source) == source.appendingPathComponent("Locales"))
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Locales"), withIntermediateDirectories: true)
        #expect(Localizer.locate(bundleResources: bundle, sourceRoot: source) == bundle.appendingPathComponent("Locales"))
        #expect(Localizer.locate(bundleResources: nil, sourceRoot: tmp.appendingPathComponent("none")) == nil)
    }

    @Test func realFilesLoad() throws {
        let dir = try #require(Localizer.locate())
        let l = Localizer(directory: dir)
        let codes = l.languages.map(\.code)
        #expect(codes.first == "en")
        #expect(codes.contains("tr"))
        for code in codes {
            for field in ["name", "locale", "percent", "dateLine", "dateTemplate", "timeTemplate"] {
                #expect(!(l.meta(field, language: code) ?? "").isEmpty, "\(code) _meta.\(field)")
            }
        }
        #expect(l.languages.first { $0.code == "tr" }?.locale.identifier == "tr_TR")
    }
}
