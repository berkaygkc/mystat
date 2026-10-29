import Foundation
import Synchronization

/// Seçili dil ve metin araması. Metinler `Locales/<dil>.json`'dan gelir; seçili dilde yoksa İngilizceden,
/// o da yoksa anahtarın kendisi döner (ekranda hiçbir zaman boş metin olmaz).
///
/// Yer tutucular `{ad}`; değiştiriciyle `{ad|poss3}` (Türkçe iyelik eki), `{ad|gen}` (Türkçe ilgi eki).
/// Değiştirici yalnızca tanımlı olduğu dilde uygulanır, diğer dillerde değer olduğu gibi yazılır.
public enum L10n {
    /// Testler ve görüntü modu dili görev başına sabitler; genel seçimin önüne geçer.
    @TaskLocal public static var override: String?
    private static let selected = Mutex<String?>(nil)

    /// Uygulama genelinde seçili dil (dil menüsü ve açılış).
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

    /// `key.one` / `key.other`; hangisi olduğu dilin `_meta.plural` kuralına bağlı. `{n}` sayıdır; biçimli sayı
    /// gerekiyorsa `args["n"]` ile verilir.
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

    /// `_meta.plural`: "one" (1 → one; varsayılan), "zero-one" (0 ve 1 → one), "none" (hep other).
    static func pluralForm(_ n: Int, rule: String?) -> String {
        switch rule {
        case "none": "other"
        case "zero-one": n == 0 || n == 1 ? "one" : "other"
        default: n == 1 ? "one" : "other"
        }
    }

    /// Dile özel yer tutucu değiştiricileri: değer → değer + ek.
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

    /// Tercih edilen diller içinden desteklenen ilki: önce tam eşleşme ("pt-BR"), sonra dil kodu ("tr-TR" → "tr").
    public static func detect(preferred: [String], available: [String]) -> String {
        for p in preferred {
            let tag = p.replacingOccurrences(of: "_", with: "-").lowercased()
            if let exact = available.first(where: { $0.lowercased() == tag }) { return exact }
            let base = String(tag.split(separator: "-").first ?? "")
            if let match = available.first(where: { $0.lowercased() == base }) { return match }
        }
        return "en"
    }
}
