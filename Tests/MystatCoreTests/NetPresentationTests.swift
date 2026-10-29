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
}
