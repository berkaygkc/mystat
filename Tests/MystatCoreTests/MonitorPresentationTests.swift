import Foundation
import Testing
@testable import MystatCore

@MainActor @Suite struct MonitorPresentationTests {
    @Test func navValues() {
        let calm = SampleSource(seed: 1).snapshot
        #expect(MonitorPresentation.navValue("overview", calm).text == "")
        #expect(MonitorPresentation.navValue("cpu", calm).text == "%14")
        #expect(MonitorPresentation.navValue("net", calm).text == "↓14,6")
        #expect(MonitorPresentation.navValue("docker", calm).text == "15")
        #expect(MonitorPresentation.navValue("sys", calm).text == "48°")
        let hot = SampleSource(seed: 1, incident: true).snapshot
        #expect(MonitorPresentation.navValue("cpu", hot).level == .crit); #expect(MonitorPresentation.navValue("sys", hot).level == .warn)
    }
    @Test func incidentSentences() {
        let s = { (k: IncidentKind) in MonitorPresentation.incidentSentence(SampleSource(seed: 1, incident: true, kind: k).snapshot) }
        #expect(s(.cpu) == "İşlemci 4 dakikadır %90'ın üzerinde. Yükün çoğu acmecorp projesinden geliyor.")
        #expect(s(.memory) == "Bellek baskısı 6 dakikadır yüksek. En çok Docker büyüyor.")
        #expect(s(.disk) == "Diskte 8 GB kaldı; son 24 saatte 14 GB azaldı.")
        #expect(s(.docker) == "acmecorp-verifier 6 dakikadır %62 CPU kullanıyor.")
        #expect(s(.heat) == "Çip 9 dakikadır ısınıyor; fanlar 4.800 dev/dk ile dönüyor.")
        #expect(s(.battery) == "Pil 30 dakikada %25 eridi; bu hızla 1 sa 10 dk yeter.")
    }
    @Test func incidentSectionAndSeries() {
        #expect(MonitorPresentation.section(for: .memory) == "mem"); #expect(MonitorPresentation.section(for: .battery) == "sys")
        #expect(MonitorPresentation.seriesKey(for: .disk) == .diskWrite)
        #expect(MonitorPresentation.inspectTitle(section: "mem") == "Bellek'te incele")
        #expect(MonitorPresentation.inspectTitle(section: "docker") == "Docker'da incele")
    }
    @Test func heatFactIsWarn() {
        let f = SampleSource(seed: 1, incident: true).snapshot.incident!.facts
        #expect(f.last == Fact("Isı", "91°", level: .warn))
    }
}
