import Foundation
import Synchronization

/// Selected language and text lookup. Texts come from `Locales/<language>.json`; if missing in the selected language, English is used,
/// and if that is missing too, the key itself is returned (the screen never shows empty text).
///
/// Placeholders are `{name}`; with a modifier, `{name|poss3}` (Turkish possessive suffix) or `{name|gen}` (Turkish genitive suffix).
/// A modifier is applied only in the language that defines it; in other languages the value is written as is.
public enum L10n {
    /// Tests and the screenshot mode pin the language per task; this overrides the global selection.
    @TaskLocal public static var override: String?
    private static let selected = Mutex<String?>(nil)

    /// The language selected app-wide (language menu and launch).
    public static func setLanguage(_ code: String) { selected.withLock { $0 = code } }

    public static var code: String { override ?? selected.withLock { $0 } ?? "en" }

    public static var current: Language { language(code, localizer: .shared) }

    static func language(_ code: String, localizer: Localizer) -> Language {
        localizer.languages.first { $0.code == code }
            ?? localizer.languages.first { $0.code == "en" }
            ?? Language(code: "en", name: "English", locale: Locale(identifier: "en_US"))
    }

    public static func t(_ key: String, _ args: [String: String] = [:]) -> String {
        t(key, args, language: code, localizer: .shared)
    }

    /// `key.one` / `key.other`; which one applies depends on the language's `_meta.plural` rule. `{n}` is the count; if a formatted
    /// number is needed, it is passed via `args["n"]`.
    public static func plural(_ key: String, _ n: Int, _ args: [String: String] = [:]) -> String {
        plural(key, n, args, language: code, localizer: .shared)
    }

    static func t(_ key: String, _ args: [String: String] = [:], language: String, localizer: Localizer) -> String {
        if let s = localizer.string(key, language: language) { return fill(s, args, language: language) }
        if let s = localizer.string(key, language: "en") { return fill(s, args, language: "en") }
        return key
    }

    static func plural(_ key: String, _ n: Int, _ args: [String: String] = [:], language: String, localizer: Localizer) -> String {
        var args = args
        if args["n"] == nil { args["n"] = String(n) }
        for lang in [language, "en"] {
            let form = pluralForm(n, rule: localizer.meta("plural", language: lang))
            for candidate in [form, "other"] {
                if let s = localizer.string("\(key).\(candidate)", language: lang) { return fill(s, args, language: lang) }
            }
        }
        return "\(key).other"
    }

    /// `_meta.plural`: "one" (1 → one; default), "zero-one" (0 and 1 → one), "none" (always other).
    static func pluralForm(_ n: Int, rule: String?) -> String {
        switch rule {
        case "none": "other"
        case "zero-one": n == 0 || n == 1 ? "one" : "other"
        default: n == 1 ? "one" : "other"
        }
    }

    /// Language-specific placeholder modifiers: value → value + suffix.
    static let modifiers: [String: [String: @Sendable (String) -> String]] = [
        "tr": ["poss3": { $0 + TurkishSuffix.possessive3(after: $0) },
               "gen": { $0 + TurkishSuffix.genitive(after: $0) }],
    ]

    static func fill(_ s: String, _ args: [String: String], language: String) -> String {
        guard s.contains("{") else { return s }
        var out = "", rest = s[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out += rest[..<open]
            let token = rest[rest.index(after: open)..<close]
            let parts = token.split(separator: "|", maxSplits: 1).map(String.init)
            if let name = parts.first, let value = args[name] {
                let modifier = parts.count > 1 ? modifiers[language]?[parts[1]] : nil
                out += modifier?(value) ?? value
            } else {
                out += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }

    /// Headline template; `{emph}` is written emphasized (`.emphasized`) and the UI colors it by level. Word order depends on the language.
    public static func emphasized(_ key: String, emph: String, _ args: [String: String] = [:]) -> AttributedString {
        let marker = "\u{E000}"
        let parts = t(key, args.merging(["emph": marker]) { a, _ in a }).components(separatedBy: marker)
        guard parts.count == 2 else { return AttributedString(parts.joined(separator: emph)) }
        var e = AttributedString(emph)
        e.inlinePresentationIntent = .emphasized
        return AttributedString(parts[0]) + e + AttributedString(parts[1])
    }

    /// The first supported language among the preferred ones. The tag is matched by trimming from the end: "zh-Hans-CN" → "zh-Hans" → "zh",
    /// "tr-TR" → "tr".
    public static func detect(preferred: [String], available: [String]) -> String {
        for p in preferred {
            var parts = p.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
            while !parts.isEmpty {
                let tag = parts.joined(separator: "-")
                if let match = available.first(where: { $0.lowercased() == tag }) { return match }
                parts.removeLast()
            }
        }
        return "en"
    }
}
