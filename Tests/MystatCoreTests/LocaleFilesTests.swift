import Foundation
import Testing
@testable import MystatCore

/// Dil dosyası bekçileri: koddaki her anahtar İngilizcede var, her dil tam ve yer tutucuları aynı, kodda Türkçe metin yok.
/// Yeni dil ekleyen katkıcı `swift test --filter LocaleFilesTests` ile denetler.
@Suite struct LocaleFilesTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let localizer = Localizer(directory: repo.appendingPathComponent("Locales"))

    /// Bir dil dosyasının düz anahtarları (`_meta` hariç).
    static func keys(_ code: String) -> [String: String] {
        let url = repo.appendingPathComponent("Locales/\(code).json")
        guard let data = try? Data(contentsOf: url), let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        return root.compactMapValues { $0 as? String }
    }

    static func sources() -> [(path: String, text: String)] {
        let base = repo.appendingPathComponent("Sources")
        let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        var out: [(String, String)] = []
        while let u = e?.nextObject() as? URL {
            guard u.pathExtension == "swift", let t = try? String(contentsOf: u, encoding: .utf8) else { continue }
            out.append((u.path.replacingOccurrences(of: repo.path + "/", with: ""), t))
        }
        return out.sorted { $0.0 < $1.0 }
    }

    /// `L10n.t/plural/emphasized` çağrılarının ilk argümanındaki anahtarlar ("panel.quit"; koşullu ifadede ikisi de).
    static func usedKeys(in text: String) -> Set<String> {
        let call = /L10n\.(?:t|plural|emphasized)\(([^,)]*)/
        let keyLiteral = /"([a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)+)"/
        var out = Set<String>()
        for c in text.matches(of: call) {
            for m in c.1.matches(of: keyLiteral) { out.insert(String(m.1)) }
        }
        return out
    }

    /// Anahtar dosyada yoksa (çoğulda `.other` de yoksa) eksik sayılır.
    static func missing(_ used: Set<String>, in keys: [String: String]) -> [String] {
        used.filter { keys[$0] == nil && keys[$0 + ".other"] == nil }.sorted()
    }

    /// Kodda değişkenle kurulan anahtarlar.
    static let dynamicKeys: [String] =
        ["overview", "cpu", "mem", "disk", "net", "docker", "sys"].map { "section.\($0)" }
        + ["cpu", "mem", "disk", "net", "docker", "sys"].flatMap { ["inspect.\($0)", "kicker.\($0)"] }
        + ["m10", "h1", "h24", "d7"].flatMap { ["range.\($0)", "range.\($0).axis"] }
        + ["ok", "warn", "crit"].map { "thermal.\($0)" }

    @Test func checkerFindsMissingKey() {
        let src = #"let a = L10n.t("panel.quit"); let b = L10n.plural(x ? "disk.items" : "no.such.key", n, ["n": "1"]); Btn(L10n.t("common.stop"), icon: "doc.on.doc")"#
        let used = Self.usedKeys(in: src)
        #expect(used == ["panel.quit", "disk.items", "no.such.key", "common.stop"])
        #expect(Self.missing(used, in: ["panel.quit": "Quit", "disk.items.other": "{n} items", "common.stop": "Stop"]) == ["no.such.key"])
    }

    @Test func everyUsedKeyExists() {
        let en = Self.keys("en")
        for (path, text) in Self.sources() {
            let miss = Self.missing(Self.usedKeys(in: text), in: en)
            #expect(miss.isEmpty, "\(path): \(miss)")
        }
        #expect(Self.missing(Set(Self.dynamicKeys), in: en).isEmpty)
    }

    static func placeholders(_ s: String) -> Set<String> {
        Set(s.matches(of: /\{([A-Za-z0-9]+)(?:\|[A-Za-z0-9]+)?\}/).map { String($0.1) })
    }

    @Test func allLanguagesComplete() {
        let en = Self.keys("en")
        for lang in Self.localizer.languages where lang.code != "en" {
            let keys = Self.keys(lang.code)
            let usesOne = Self.localizer.meta("plural", language: lang.code) != "none"
            let required = en.keys.filter { usesOne || !$0.hasSuffix(".one") }
            let missing = required.filter { keys[$0] == nil }.sorted()
            #expect(missing.isEmpty, "\(lang.code) eksik: \(missing)")
            let extra = keys.keys.filter { en[$0] == nil }.sorted()
            #expect(extra.isEmpty, "\(lang.code) fazla: \(extra)")
            for (k, v) in keys {
                guard let e = en[k] else { continue }
                #expect(Self.placeholders(v) == Self.placeholders(e), "\(lang.code) \(k): \(Self.placeholders(v)) ≠ \(Self.placeholders(e))")
            }
        }
    }

    /// `Locales/` içindeki her dosya okunabilir olmalı: bozuk JSON ya da `_meta`sız dosya sessizce düşer, dil listede görünmez.
    static func unloadable(in dir: URL) -> [String] {
        let loaded = Set(Localizer(directory: dir).languages.map(\.code))
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { u in
            let code = u.deletingPathExtension().lastPathComponent
            guard loaded.contains(code), let data = try? Data(contentsOf: u),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return code }
            return root.contains { $0.key != "_meta" && !($0.value is String) } ? code : nil
        }.sorted()
    }

    @Test func checkerFindsUnloadableFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"_meta": {"name": "English", "locale": "en_US"}, "a": "A"}"#.write(to: dir.appendingPathComponent("en.json"), atomically: true, encoding: .utf8)
        try #"{"_meta": {"name": "Deutsch", "locale": "de_DE"}, "a": "A""#.write(to: dir.appendingPathComponent("de.json"), atomically: true, encoding: .utf8)
        try #"{"_meta": {"name": "Français", "locale": "fr_FR"}, "a": 1}"#.write(to: dir.appendingPathComponent("fr.json"), atomically: true, encoding: .utf8)
        #expect(Self.unloadable(in: dir) == ["de", "fr"])
    }

    @Test func everyFileLoads() {
        #expect(Self.unloadable(in: Self.repo.appendingPathComponent("Locales")).isEmpty)
        for lang in Self.localizer.languages {
            let empty = Self.keys(lang.code).filter { $0.value.isEmpty }.keys.sorted()
            #expect(empty.isEmpty, "\(lang.code) boş değerler: \(empty)")
        }
    }

    /// Konum izni penceresini macOS çizer: metni Info.plist'ten (İngilizce) ya da sistem diline göre `<dil>.lproj`'dan alır.
    @Test func infoPlistIsEnglishAndLocalized() throws {
        let keys = ["NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription"]
        let plist = try #require(NSDictionary(contentsOf: Self.repo.appendingPathComponent("Resources/Info.plist")) as? [String: Any])
        #expect(plist["CFBundleDevelopmentRegion"] as? String == "en")
        for k in keys {
            let v = try #require(plist[k] as? String)
            #expect(!v.contains(/[çğıöşüÇĞİÖŞÜ]/), "\(k): \(v)")
        }
        let tr = try #require(NSDictionary(contentsOf: Self.repo.appendingPathComponent("Resources/tr.lproj/InfoPlist.strings")) as? [String: String])
        for k in keys { #expect(tr[k]?.contains("Wi") == true, "tr \(k)") }
    }

    @Test func metaComplete() {
        #expect(Self.localizer.languages.count >= 2)
        for lang in Self.localizer.languages {
            for field in ["name", "locale", "percent", "dateLine", "dateTemplate", "timeTemplate"] {
                #expect(!(Self.localizer.meta(field, language: lang.code) ?? "").isEmpty, "\(lang.code) _meta.\(field)")
            }
            #expect(Self.localizer.meta("percent", language: lang.code)?.contains("{value}") == true)
            #expect(["one", "zero-one", "none", nil].contains(Self.localizer.meta("plural", language: lang.code)))
            let f = DateFormatter(); f.locale = lang.locale; f.dateFormat = Self.localizer.meta("dateLine", language: lang.code)
            #expect(!f.string(from: Date()).isEmpty)
        }
    }

    /// Kodda kullanıcıya görünen Türkçe metin kalmamalı. İzin listesi: Türkçe ek kuralları ve ekrana çıkmayan iç adlar.
    @Test func noTurkishLiteralsInSources() {
        let allowedFiles = ["Sources/MystatCore/Format/TurkishSuffix.swift"]
        let allowed = [#""\u{0}küçük""#, #""Diğer""#, #""…diğer""#]   // DiskNode.smallFilesName, ScanIndex.otherName, balon kimliği
        let turkish = /"(?:[^"\\]|\\.)*[çğıöşüÇĞİÖŞÜ](?:[^"\\]|\\.)*"/
        for (path, text) in Self.sources() where !allowedFiles.contains(path) {
            for (i, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = Self.stripComment(String(raw))
                for m in line.matches(of: turkish) where !allowed.contains(String(m.0)) {
                    Issue.record("\(path):\(i + 1): \(m.0)")
                }
            }
        }
    }

    /// Satırın açıklama kısmını atar (dize içindeki "//" korunur).
    static func stripComment(_ line: String) -> String {
        var inString = false, escaped = false, prev: Character = " "
        for (i, c) in line.enumerated() {
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" { inString = true } else if c == "/", prev == "/" {
                return String(line.prefix(i - 1))
            }
            prev = c
        }
        return line
    }
}
