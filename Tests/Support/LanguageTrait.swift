import MystatCore
import Testing

/// Suite ya da testi bir dilde çalıştırır: `@Suite(.language("tr"))`. Dil görev yereli (`L10n.override`) olduğundan
/// paralel testler birbirinin dilini değiştirmez.
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
