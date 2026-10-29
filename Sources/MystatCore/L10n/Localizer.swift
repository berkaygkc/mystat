import Foundation

/// Bir dil dosyası: `Locales/<code>.json`.
public struct Language: Sendable, Hashable, Identifiable {
    /// Dosya adı: "en", "tr".
    public let code: String
    /// Kendi dilinde adı: "English", "Türkçe".
    public let name: String
    /// Sayı, tarih ve büyük/küçük harf için (`_meta.locale`).
    public let locale: Locale
    public var id: String { code }
}

/// `Locales/` klasöründeki dil dosyalarını okur. Dosya başına `_meta` (ad, locale, biçim kalıpları) ve düz
/// `"anahtar": "metin"` çiftleri. Okunamayan ya da `_meta.name`/`_meta.locale` eksik dosya yok sayılır.
public final class Localizer: Sendable {
    public static let shared = Localizer(directory: locate())

    /// İngilizce başta, sonra kendi adlarına göre.
    public let languages: [Language]
    private let strings: [String: [String: String]]
    private let metas: [String: [String: String]]

    public convenience init(directory: URL) { self.init(directory: Optional(directory)) }

    init(directory: URL?) {
        var strings: [String: [String: String]] = [:], metas: [String: [String: String]] = [:], languages: [Language] = []
        let files = directory.flatMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) } ?? []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let meta = root["_meta"] as? [String: String],
                  let name = meta["name"], let locale = meta["locale"] else { continue }
            let code = file.deletingPathExtension().lastPathComponent
            strings[code] = root.compactMapValues { $0 as? String }
            metas[code] = meta
            languages.append(Language(code: code, name: name, locale: Locale(identifier: locale)))
        }
        self.languages = languages.sorted { $0.code == "en" ? $1.code != "en" : ($1.code != "en" && $0.name < $1.name) }
        self.strings = strings
        self.metas = metas
    }

    public func string(_ key: String, language: String) -> String? { strings[language]?[key] }

    public func meta(_ field: String, language: String) -> String? { metas[language]?[field] }

    /// Paketin `Contents/Resources/Locales`'i, yoksa kaynak ağacındaki `Locales/` (geliştirme ve testler).
    static func locate() -> URL? {
        // Bu dosya: <depo>/Sources/MystatCore/L10n/Localizer.swift
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return locate(bundleResources: Bundle.main.resourceURL, sourceRoot: repo)
    }

    static func locate(bundleResources: URL?, sourceRoot: URL) -> URL? {
        let fm = FileManager.default
        for dir in [bundleResources?.appendingPathComponent("Locales"), sourceRoot.appendingPathComponent("Locales")] {
            if let dir, fm.fileExists(atPath: dir.path) { return dir }
        }
        return nil
    }
}
