import CryptoKit
import Foundation
import Testing

/// Hygiene checks for the public repository:
/// - comments and script output are in English;
/// - comments don't point at internal planning documents;
/// - no private term appears in any tracked file. The terms are stored only as SHA-256 digests.
@Suite struct RepoHygieneTests {
    static let repo = LocaleFilesTests.repo

    /// Tracked files (repo-relative). Without git (e.g. a source archive), the source folders are walked instead.
    static func trackedFiles() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo.path, "ls-files"]
        let out = Pipe()
        p.standardOutput = out; p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if p.terminationStatus == 0 { return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init) }
        }
        var files: [String] = []
        for dir in ["Sources", "Tests", "scripts", "tools", "Locales", "Resources"] {
            let e = FileManager.default.enumerator(at: repo.appendingPathComponent(dir), includingPropertiesForKeys: nil)
            while let u = e?.nextObject() as? URL { files.append(u.path.replacingOccurrences(of: repo.path + "/", with: "")) }
        }
        return files
    }

    static func text(_ path: String) -> String? {
        guard !["png", "icns"].contains((path as NSString).pathExtension) else { return nil }
        return try? String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8)
    }

    static var turkish: Regex<Substring> { /[çğıöşüÇĞİÖŞÜ]/ }
    static var internalRef: Regex<Substring> { /§\d|Review Focus|\bTask \d|\b[Ff]az \d|\b[Mm]ockup|\bspec\b/ }

    /// The comment part of a Swift line (after `//` outside a string literal), or nil.
    static func swiftComment(_ line: String) -> String? {
        let code = LocaleFilesTests.stripComment(line)
        return code.count < line.count ? String(line.dropFirst(code.count)) : nil
    }

    /// Files checked in full: everything in them (comments and printed output) must be English.
    static func checkedWhole(_ path: String) -> Bool {
        path.hasPrefix("scripts/") || path.hasPrefix("tools/") || ["Package.swift", "Resources/Info.plist", ".gitignore"].contains(path)
    }

    /// Lines to check in a file: comments for Swift sources and tests, every line for scripts and config.
    static func checkedLines(_ path: String, _ text: String) -> [(Int, String)] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if checkedWhole(path) { return Array(zip(1..., lines)) }
        guard path.hasSuffix(".swift"), path.hasPrefix("Sources/") || path.hasPrefix("Tests/") else { return [] }
        return zip(1..., lines).compactMap { n, l in swiftComment(l).map { (n, $0) } }
    }

    /// Lowercase words whose SHA-256 is in `digests`.
    static func privateHits(_ text: String, digests: Set<String>) -> [String] {
        Set(text.lowercased().matches(of: /[a-z0-9]+/).map { String($0.0) })
            .filter { digests.contains(SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined()) }
            .sorted()
    }

    /// Names that must never appear in the repository (product, vendor, workplace and tool names), as SHA-256 digests.
    static let privateDigests: Set<String> = [
        "317731e7633fb37ccaa7bbd4a78c310ffa3e5217b049019939dcd8947c6afef2",
        "a30d8f4a7a90da3d2dc9e470253e2378c3da8eab715f9d4e3b5d5536052b5629",
        "848abaab6847d7f07189a7f5cca6b8af6cb52ae3227bd352609741f75ac1b15e",
        "52b9879d291a7078dc24585f48ca91390d944650b7bc18c4d432d905bd1e9eeb",
        "d63f4a0cdaab52726d1ce895e4ac8c3507049e617b0a97d0a0af508bdad34a8d",
        "444d4d18612a99912b7f5841eeede02e69d402ee1e48c3682dc45aa38fa7a98f",
        "c4599aab5cbf87f8189071b86ce3c16a7dc83fd6a365466c4374939ef6b04812",
        "392a5bcbd71a7db2cfb9796c633326f7fba6730bdb0c801d3b0fd30886821000",
        "59a2ea36c20b30a30f3aa251b346188d5afbeddfca2d496e67b0c2d9eb74a345",
        "2d0d38e68843216f183110ca3f4212682e1ccf86371e15fbdc0a3f24e697cfe0",
        "94805aea13420685a2929f6859071e2e12d650c6609c0d91ed602a9bf227af39",
        "6a9bb179400afb21957db1e9f878f0c8a7dd1bb443303855c43e0597647a3457",
        "db77ca6bb991f807190b0c8cb00c09b74094f089a2efb2a0e629d00540973846",
    ]

    /// The author's name (in the copyright line) is a proper name, not Turkish text.
    static let author = "Berkay G\u{F6}k\u{E7}e"

    /// The maintainer's home folder; built from parts so this file doesn't contain it.
    static let localHome = "/Users/" + "berkay" + "gokce"

    @Test func checkerSelfTest() {
        let g = "\u{11F}", c = "\u{E7}"   // Turkish letters, escaped so this file stays clean
        #expect(Self.swiftComment("let u = \"http://x\" // note \(g)") == "// note \(g)")
        #expect(Self.swiftComment("let u = \"http://x\"") == nil)
        #expect(Self.checkedLines("Sources/A.swift", "let a = \"\(c)\"\n// \(g)\n").map(\.0) == [2])
        #expect(Self.checkedLines("scripts/x.sh", "echo \"\(c)\"").count == 1)
        #expect("// see §6.4".contains(Self.internalRef))
        let made = SHA256.hash(data: Data("zorbulax".utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(Self.privateHits("Hello Zorbulax-world", digests: [made]) == ["zorbulax"])
    }

    @Test func commentsAreEnglish() {
        for path in Self.trackedFiles() {
            guard let text = Self.text(path) else { continue }
            for (n, line) in Self.checkedLines(path, text) where line.replacingOccurrences(of: Self.author, with: "").contains(Self.turkish) {
                Issue.record("\(path):\(n): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
    }

    /// The unpublished design prototype must not be named anywhere in code either (test names included).
    @Test func noPrototypeNames() {
        let word = "mock" + "up"   // built from parts so this file passes its own check
        for path in Self.trackedFiles() where path.hasSuffix(".swift") || path.hasSuffix(".sh") {
            guard let text = Self.text(path) else { continue }
            #expect(!text.lowercased().contains(word), "\(path)")
        }
    }

    @Test func noInternalReferences() {
        for path in Self.trackedFiles() {
            guard let text = Self.text(path) else { continue }
            for (n, line) in Self.checkedLines(path, text) where line.contains(Self.internalRef) {
                Issue.record("\(path):\(n): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
    }

    /// README statements that must stay true: data location, minimum macOS, license, version, screenshots.
    @Test func readmeClaimsMatchCode() throws {
        let readme = try #require(Self.text("README.md"))
        let history = try #require(Self.text("Sources/MystatLive/HistoryStore.swift"))
        #expect(history.contains(#"appendingPathComponent("mystat")"#) && history.contains(#""history.sqlite""#))
        #expect(readme.contains("~/Library/Application Support/mystat/history.sqlite"))
        let scan = try #require(Self.text("Sources/MystatLive/DiskScanController.swift"))
        #expect(scan.contains("mystat/diskscan.cache") && readme.contains("diskscan.cache"))
        let package = try #require(Self.text("Package.swift"))
        let macOS = try #require(package.firstMatch(of: /\.macOS\("(\d+)/)).1
        #expect(readme.contains("macOS \(macOS) or later"))
        #expect(Self.text("LICENSE")?.hasPrefix("MIT License") == true)
        let plist = try #require(NSDictionary(contentsOf: Self.repo.appendingPathComponent("Resources/Info.plist")))
        let version = try #require(plist["CFBundleShortVersionString"] as? String)
        let changelog = try #require(Self.text("CHANGELOG.md"))
        #expect(changelog.firstMatch(of: /\n## (\S+)/).map { String($0.1) } == version)
        // Images, including the dark variants a <picture> switches to.
        let images = readme.matches(of: /(?:src|srcset)="([^"]+\.png)"/).map { String($0.1) }
        #expect(!images.isEmpty)
        for path in images {
            #expect(FileManager.default.fileExists(atPath: Self.repo.appendingPathComponent(path).path), "\(path)")
        }
    }

    /// A named defaults suite leaves a plist in ~/Library/Preferences on every test run; tests use `scratchDefaults()`.
    @Test func testsUseScratchDefaults() {
        let named = "UserDefaults(suite" + "Name:"   // built from parts so this line doesn't match itself
        for path in Self.trackedFiles() where path.hasPrefix("Tests/") && path.hasSuffix(".swift") && !path.hasPrefix("Tests/Support/") {
            guard let text = Self.text(path) else { continue }
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where line.contains(named) {
                Issue.record("\(path):\(n + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
    }

    /// Code adapted from d3-hierarchy (ISC) must carry its notice, in the repository and in the app bundle.
    @Test func thirdPartyNoticesPresent() throws {
        let notices = try #require(Self.text("THIRD_PARTY_NOTICES.md"))
        #expect(notices.contains("d3-hierarchy") && notices.contains("ISC License") && notices.contains("Mike Bostock"))
        #expect(Self.text("Sources/MystatCore/Bubbles/CirclePack.swift")?.contains("THIRD_PARTY_NOTICES.md") == true)
        let makeApp = try #require(Self.text("scripts/make-app.sh"))
        #expect(makeApp.contains("THIRD_PARTY_NOTICES.md") && makeApp.contains("LICENSE"))
    }

    @Test func noPrivateTerms() {
        for path in Self.trackedFiles() {
            guard let text = Self.text(path) else { continue }
            let hits = Self.privateHits(text, digests: Self.privateDigests)
            #expect(hits.isEmpty, "\(path): \(hits.count) private term(s)")
            #expect(!text.contains(Self.localHome), "\(path): local user path")
        }
    }
}
