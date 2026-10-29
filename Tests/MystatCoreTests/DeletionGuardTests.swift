import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

@Suite(.language("tr")) struct DeletionGuardTests {
    @Test func protectedPaths() {
        for p: [String] in [[], ["Library"], ["Documents"], ["Library", "Containers"], ["Library", "Mobile Documents"], ["Downloads"], ["Movies"]] {
            #expect(DeletionGuard.reason(path: p) != nil, "\(p)")
        }
        for p: [String] in [["Library", "Caches"], ["Documents", "eski"], ["Library", "Containers", "com.docker.docker"], [".npm"]] {
            #expect(DeletionGuard.reason(path: p) == nil, "\(p)")
        }
        #expect(DeletionGuard.reason(path: ["Library"]) == "Library macOS için gerekli; içindekileri seçebilirsin.")
    }

    @MainActor @Test func basketRefusesProtected() {
        let t = SampleSource(seed: 1).diskTree; var b = SelectionBasket()
        #expect(b.toggle(["Library"], in: t) == .notSelectable)
        #expect(b.toggle(["Movies"], in: t) == .notSelectable)
        #expect(b.toggle(["Library", "Caches"], in: t) == .added)
        #expect(b.items.map(\.name) == ["Caches"])
    }

    @Test func deleteToast() {
        #expect(DeleteOutcome(freedGB: 12.4, failed: [], changed: []).toast(trash: false) == "12 GB boşaldı")
        #expect(DeleteOutcome(freedGB: 2.5, failed: [], changed: []).toast(trash: true) == "2,5 GB çöpe taşındı")
        #expect(DeleteOutcome(freedGB: 2.5, failed: [], changed: [], simulated: true).toast(trash: false) == "2,5 GB boşaldı (örnek)")
        #expect(DeleteOutcome(freedGB: 2.5, failed: ["a"], changed: []).toast(trash: false) == "2,5 GB boşaldı · 1 öğe silinemedi")
        #expect(DeleteOutcome(freedGB: 0, failed: ["a", "b"], changed: []).toast(trash: false) == "2 öğe silinemedi")
        #expect(DeleteOutcome(freedGB: 0, failed: [], changed: ["a"]).toast(trash: false) == "1 öğe taramadan sonra değişmiş; yeniden tara")
        #expect(DeleteOutcome(freedGB: 1.2, failed: [], changed: ["a"]).toast(trash: true) == "1,2 GB çöpe taşındı · 1 öğe taramadan sonra değişmiş; yeniden tara")
    }
}
