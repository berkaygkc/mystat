import MystatCore
import Testing

/// Runs a suite or test in a given language: `@Suite(.language("tr"))`. Because the language is a task-local (`L10n.override`),
/// parallel tests do not change each other's language.
public struct LanguageTrait: TestTrait, SuiteTrait, TestScoping {
    let code: String
    public var isRecursive: Bool { true }

    public func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        try await L10n.$override.withValue(code) { try await function() }
    }
}

extension Trait where Self == LanguageTrait {
    public static func language(_ code: String) -> Self { LanguageTrait(code: code) }
}
