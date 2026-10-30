import Foundation

/// A language file: `Locales/<code>.json`.
public struct Language: Sendable, Hashable, Identifiable {
    /// File name: "en", "tr".
    public let code: String
    /// Name in the language itself (English is "English", Turkish is written in Turkish).
    public let name: String
    /// Used for numbers, dates and casing (`_meta.locale`).
    public let locale: Locale
    public var id: String { code }
}

/// Reads the language files in the `Locales/` folder. Each file has `_meta` (name, locale, format patterns) and flat
/// `"key": "text"` pairs. A file that is unreadable or lacks `_meta.name`/`_meta.locale` is ignored.
public final class Localizer: Sendable {
    public static let shared = Localizer(directory: locate())

    /// English first, then sorted by their own names.
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
            strings[code] = root.compactMapValues { ($0 as? String).flatMap { $0.isEmpty ? nil : $0 } }   // empty = untranslated: the English text shows instead
            metas[code] = meta
            languages.append(Language(code: code, name: name, locale: Locale(identifier: locale)))
        }
        self.languages = languages.sorted { $0.code == "en" ? $1.code != "en" : ($1.code != "en" && $0.name < $1.name) }
        self.strings = strings
        self.metas = metas
    }

    public func string(_ key: String, language: String) -> String? { strings[language]?[key] }

    public func meta(_ field: String, language: String) -> String? { metas[language]?[field] }

    /// The bundle's `Contents/Resources/Locales`, otherwise `Locales/` in the source tree (development and tests).
    static func locate() -> URL? {
        // This file: <repo>/Sources/MystatCore/L10n/Localizer.swift
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
