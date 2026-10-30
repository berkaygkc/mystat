import Foundation

/// A defaults suite of its own for one test, stored in the temporary folder. A plain suite name would leave a plist in
/// ~/Library/Preferences on every run (deleting it doesn't help: cfprefsd writes it back); a suite name that is an
/// absolute path is stored at that path instead.
public func scratchDefaults() -> UserDefaults {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("mystat-tests/\(UUID().uuidString)").path
    guard let defaults = UserDefaults(suiteName: path) else { fatalError("no defaults suite at \(path)") }
    return defaults
}
