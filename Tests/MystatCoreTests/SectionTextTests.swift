import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

@MainActor @Suite(.language("tr")) struct SectionTextTests {
    @Test func memory() {
        let h = SectionText.memory(SampleSource(seed: 1).snapshot)
        #expect(h.title == "%78 dolu,"); #expect(h.soft == "ama baskı düşük."); #expect(h.level == .ok)
        #expect(h.lede == "48 GB'ın 37,6 GB'ı kullanımda. macOS diske yazmak yerine belleği sıkıştırıyor: 30 GB'lık veriyi 14,4 GB'a sığdırmış. Swap yok, yani makine sıkışmış değil.")
        let hot = SectionText.memory(SampleSource(seed: 1, incident: true, kind: .memory).snapshot)
        #expect(hot.soft == "ve baskı yüksek."); #expect(hot.level == .crit); #expect(hot.lede.hasSuffix("Swap 3,2 GB'a çıktı; makine zorlanıyor."))
    }
    @Test func network() {
        #expect(SectionText.networkLede(SampleSource(seed: 1).snapshot)
                == "Wi‑Fi · Ev ağı. Bugün 12,4 GB indirildi, 1,8 GB gönderildi. Şu an en çok Docker indiriyor.")
    }
    @Test func docker() {
        let calm = SectionText.docker(SampleSource(seed: 1).snapshot)
        #expect(calm.title == "15 container ayakta,"); #expect(calm.soft == "hepsi sakin.")
        #expect(calm.lede == "Container'lar toplam %4 CPU ve 2,5 GB bellek kullanıyor. Docker'ın diski 27 GB; 12,6 GB'ı geri kazanılabilir.")
        let busy = SectionText.docker(SampleSource(seed: 1, incident: true).snapshot)
        #expect(busy.title == "15 container ayakta."); #expect(busy.soft == "Biri yoğun çalışıyor.")
        #expect(busy.lede.hasPrefix("acmecorp-verifier tek başına %62 CPU kullanıyor; container'ların toplamı %100."))
    }
    @Test func system() {
        let calm = SectionText.system(SampleSource(seed: 1).snapshot)
        #expect(String(calm.title.characters) == "Serin ve sessiz."); #expect(calm.level == .ok)
        #expect(calm.lede == "Çip 48°, fanlar duruyor. Prizdesin, pil tam dolu ve sağlığı iyi.")
        let heat = SectionText.system(SampleSource(seed: 1, incident: true).snapshot)
        #expect(String(heat.title.characters) == "Çip ısınıyor: 91°"); #expect(heat.level == .warn)
        let bat = SectionText.system(SampleSource(seed: 1, incident: true, kind: .battery).snapshot)
        #expect(String(bat.title.characters) == "Pil hızlı eriyor: 30 dk'da %25")
    }
}
