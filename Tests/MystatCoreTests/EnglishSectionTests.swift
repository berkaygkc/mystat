import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

/// The English section texts, one example each.
@MainActor @Suite(.language("en")) struct EnglishSectionTests {
    @Test func memory() {
        let h = SectionText.memory(SampleSource(seed: 1).snapshot)
        #expect(h.title == "78% full,"); #expect(h.soft == "but pressure is low.")
        #expect(h.lede == "37.6 GB of 48 GB in use. macOS compresses memory instead of writing to disk: 30 GB of data fits in 14.4 GB. No swap, so the machine isn't squeezed.")
    }

    @Test func network() {
        #expect(SectionText.networkLede(SampleSource(seed: 1).snapshot).contains("downloaded today"))
        #expect(NetPresentation.perAppNote(available: true, ready: false, empty: true) == "Measuring…")
        #expect(NetPresentation.accessLine(.needsPermission)?.action == "Allow")
        let wifi = NetLink(bsdName: "en0", displayName: "Wi‑Fi", localIP: "192.168.1.42", router: "192.168.1.1", dns: ["192.168.1.1"],
                           wifi: WiFiReading(ssid: "Home", rssi: -48, noise: -90, txRateMbps: 1201, channel: 44, bandGHz: 5), linkMbps: nil)
        let f = NetPresentation.facts(wifi)
        #expect(f.map(\.label) == ["Band", "Link speed", "Signal", "Local IP", "Router", "DNS", "Interface"])
        #expect(f[0].value == "5 GHz · channel 44"); #expect(f[1].value == "1,201 Mb/s"); #expect(f[2].value == "Very good · −48 dBm")
    }

    @Test func docker() {
        let calm = SectionText.docker(SampleSource(seed: 1).snapshot)
        #expect(calm.title == "15 containers up,"); #expect(calm.soft == "all calm.")
        #expect(calm.lede == "Containers use 4% CPU and 2.5 GB of memory in total. Docker's disk is 27 GB; 12.6 GB can be reclaimed.")
        let src = SampleSource(seed: 1); src.dockerRunning = false
        #expect(SectionText.docker(src.snapshot).title == "Docker isn't running.")
        #expect(DockerPresentation.progress(.stop(id: "x", name: "x")) == "Stopping…")
    }

    @Test func disk() {
        let s = SampleSource(seed: 1)
        let none = SectionText.disk(s.snapshot, home: nil, freedGB: 0)
        #expect(none.title == "62% full."); #expect(none.soft == "175 GB free.")
        let scanned = SectionText.disk(s.snapshot, home: s.diskTree.root, freedGB: 0)
        #expect(scanned.lede.hasPrefix("Your home folder is "))
        #expect(ScanPhase.ready(scannedAt: Date()).validityText(now: Date()) == "Scan valid for 60 more min")
        #expect(DiskPresentation.accessNote(fullDiskAccess: true, scanned: true, inaccessible: 3) == "3 folders couldn't be read (protected by macOS)")
    }

    @Test func system() {
        let s = SampleSource(seed: 1).snapshot
        #expect(String(SectionText.system(s).title.characters) == "Cool and quiet.")
        #expect(SectionText.system(s).lede.hasPrefix("Chip 48°, fans stopped. Plugged in, battery full"))   // "and healthy": sample data
        #expect(SystemPresentation.gpuPill(s.system).0 == "Calm")
    }

    @Test func deletion() {
        let t = SampleSource(seed: 1).diskTree; var b = SelectionBasket()
        _ = b.toggle(["Documents", "apps"], in: t)
        #expect(b.confirmMessage(mode: .permanent) == "31 GB will be freed right away. This can't be undone.")
        #expect(b.confirmTitle(mode: .trash) == "Move apps to the Trash?")
        #expect(b.buttonTitle(mode: .permanent) == "Delete")
        _ = b.toggle(["Downloads", "Xcode_26.2.xip"], in: t); _ = b.toggle([".npm"], in: t); _ = b.toggle(["Library", "Caches"], in: t)
        #expect(b.confirmMessage(mode: .trash) == "apps, Caches, Xcode_26.2.xip and 1 more item. 59 GB will go to the Trash; you can restore it until you empty the Trash.")
        #expect(b.buttonTitle(mode: .trash) == "Trash 4 Items")
        #expect(DeletionGuard.reason(path: ["Library"]) == "Library is needed by macOS; you can select what's inside.")
        #expect(DeleteOutcome(freedGB: 2.5, failed: ["a"], changed: []).toast(trash: true) == "2.5 GB moved to the Trash · 1 item couldn't be deleted")
        #expect(Breadcrumbs.make([]).first?.name == "Home")
    }
}
