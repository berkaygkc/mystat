import Foundation
import Testing
@testable import MystatCore

@MainActor @Suite struct NetPresentationTests {
    static let wifi = NetLink(bsdName: "en0", displayName: "Wi‑Fi", localIP: "192.168.1.42", router: "192.168.1.1",
                              dns: ["1.1.1.1", "8.8.8.8"],
                              wifi: WiFiReading(ssid: "Ev", rssi: -48, noise: -90, txRateMbps: 1201, channel: 44, bandGHz: 5), linkMbps: nil)

    @Test func factsMatchMockup() {
        #expect(NetPresentation.facts(Self.wifi) == SampleData.netDetails)
    }

    @Test func factsWired() {
        let l = NetLink(bsdName: "en5", displayName: "Ethernet", localIP: "10.0.0.5", router: "10.0.0.1", dns: ["10.0.0.1"], wifi: nil, linkMbps: 1000)
        #expect(NetPresentation.facts(l) == [Fact("Bağlantı hızı", "1.000 Mb/sn"), Fact("Yerel IP", "10.0.0.5"), Fact("Yönlendirici", "10.0.0.1"),
                                             Fact("DNS", "10.0.0.1"), Fact("Arayüz", "en5")])
    }

    @Test func factsDisconnected() {
        let l = NetLink(bsdName: "en0", displayName: "Wi‑Fi", localIP: nil, router: nil, dns: [], wifi: nil, linkMbps: nil)
        #expect(NetPresentation.facts(l) == [Fact("Yerel IP", "—"), Fact("Yönlendirici", "—"), Fact("DNS", "—"), Fact("Arayüz", "en0")])
    }

    @Test func dnsShowsFirstThree() {
        var l = Self.wifi; l.dns = ["1.1.1.1", "8.8.8.8", "9.9.9.9", "8.8.4.4"]
        #expect(NetPresentation.facts(l).first { $0.label == "DNS" }?.value == "1.1.1.1, 8.8.8.8, 9.9.9.9")
    }

    @Test func signalWords() {
        #expect(NetPresentation.signalWord(rssi: -48) == "Çok iyi")
        #expect(NetPresentation.signalWord(rssi: -55) == "Çok iyi")
        #expect(NetPresentation.signalWord(rssi: -60) == "İyi")
        #expect(NetPresentation.signalWord(rssi: -70) == "Orta")
        #expect(NetPresentation.signalWord(rssi: -80) == "Zayıf")
    }

    @Test func bandText() {
        var l = Self.wifi
        l.wifi?.bandGHz = 2.4; l.wifi?.channel = 6
        #expect(NetPresentation.facts(l).first?.value == "2,4 GHz · kanal 6")
        l.wifi?.bandGHz = 6; l.wifi?.channel = 37
        #expect(NetPresentation.facts(l).first?.value == "6 GHz · kanal 37")
    }

    @Test func displayNameNoBreak() {
        #expect(NetPresentation.displayName("Wi-Fi") == "Wi\u{2011}Fi")
        #expect(NetPresentation.displayName("Ethernet") == "Ethernet")
    }

    @Test func ledeVariants() {
        let src = SampleSource(seed: 1)
        var s = src.snapshot
        #expect(SectionText.networkLede(s) == "Wi‑Fi · Ev ağı. Bugün 12,4 GB indirildi, 1,8 GB gönderildi. Şu an en çok Docker indiriyor.")
        s.net.ssid = ""
        #expect(SectionText.networkLede(s) == "Wi‑Fi arayüzü. Bugün 12,4 GB indirildi, 1,8 GB gönderildi. Şu an en çok Docker indiriyor.")
        for i in s.groups.indices { s.groups[i].netMBps = 0.01 }
        #expect(SectionText.networkLede(s) == "Wi‑Fi arayüzü. Bugün 12,4 GB indirildi, 1,8 GB gönderildi.")
        #expect(s.net.ssidAccess == .known); #expect(s.net.perAppAvailable)
    }

    @Test func accessLines() {
        #expect(NetPresentation.accessLine(.needsPermission)?.text == "Ağ adı için konum izni gerekiyor.")
        #expect(NetPresentation.accessLine(.needsPermission)?.action == "İzin ver")
        #expect(NetPresentation.accessLine(.denied)?.text == "Ağ adını görmek için Sistem Ayarları'nda konum izni ver.")
        #expect(NetPresentation.accessLine(.denied)?.action == "Ayarları aç")
        #expect(NetPresentation.accessLine(.known) == nil); #expect(NetPresentation.accessLine(.notWiFi) == nil)
        #expect(NetPresentation.locationSettingsURL.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
    }

    @Test func networkUsersFilters() {
        let sample = SampleSource(seed: 1).snapshot.groups
        #expect(GroupPresentation.networkUsers(sample).map(\.id) == GroupPresentation.sorted(sample, by: .network).map(\.id))   // örnek aynı
        var many = (0..<15).map { i in var g = sample[0]; g.netMBps = Double(15 - i); return g }
        many[3].netMBps = 0
        let users = GroupPresentation.networkUsers(many)
        #expect(users.count == 12); #expect(users.allSatisfy { $0.netMBps > 0 })
        #expect(users.map(\.netMBps) == users.map(\.netMBps).sorted(by: >))
    }

    @Test func latencyText() {
        #expect(NetPresentation.latencyText(.nan) == "—")
        #expect(NetPresentation.latencyText(18) == "18 ms")
        #expect(NetPresentation.latencyText(3.6) == "4 ms")
    }
}
