import Foundation
import MystatCore
import MystatTestSupport
import Testing
@testable import MystatUI

/// Arayüz metinlerinin İngilizcesi, birer örnekle.
@MainActor @Suite(.language("en")) struct EnglishUITests {
    @Test func stopTexts() {
        let src = SampleSource(seed: 1)
        let g = src.snapshot.groups.first { $0.id == "next-web" }!
        let soft = Actions.stop(g, force: false, source: src), hard = Actions.stop(g, force: true, source: src)
        #expect(soft.title == "Stop Next.js dev · acmecorp/web · :3011?")
        #expect(soft.message == "3 processes will be asked to quit. If they don't respond, you can force quit.")
        #expect(hard.confirm == "Force Quit")
        #expect(Actions.stopToast(g, force: true, .done(count: 3)) == "Next.js dev was force quit")
        #expect(Actions.stopToast(g, force: false, .notFound) == "Next.js dev already quit")
    }

    @Test func diskAndSections() {
        #expect(DiskUIState.busyText == "Can't delete while scanning; you can once it finishes.")
        #expect(UIText.sectionKicker(.net) == "NETWORK"); #expect(UIText.sectionKicker(.overview) == "NOW")
        #expect(UIText.quit == "Quit mystat")
    }
}
