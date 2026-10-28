import Foundation
import Testing
@testable import MystatCore

@MainActor @Suite struct GroupPresentationTests {
    @Test func diagnosisText() {
        let s = SampleSource(seed: 1, incident: true); let g = s.snapshot.groups.first { $0.id == "next-web" }!
        let t = GroupPresentation.diagnosis(g, incident: s.snapshot.incident)
        #expect(t.hasPrefix("Next.js dev (acmecorp/web · :3011) şu an 3,1 çekirdek CPU ve 2,4 GB bellek kullanıyor."))
        #expect(t.contains("Son 4 dakikadır yüksek (başlangıç 08:41, toplam CPU zirvesi %97)."))
        #expect(t.contains("Port: 3011"))
        #expect(t.hasSuffix("Not: başlatan terminal kapanmış, süreç sahipsiz çalışıyor."))
    }
    @Test func incidentKindHeadlines() {
        let t = { (k: IncidentKind) in String(GroupPresentation.panelHeadline(SampleSource(seed: 1, incident: true, kind: k).snapshot).title.characters) }
        #expect(t(.memory) == "Bellek baskısı yükseldi; en çok Docker büyüdü."); #expect(t(.disk) == "Diskte 8 GB kaldı.")
        #expect(t(.docker) == "acmecorp-verifier 6 dakikadır yoğun."); #expect(t(.heat) == "Çip ısınıyor: 91°.")
        #expect(t(.battery) == "Pil hızlı eriyor: 30 dk'da %25.")
    }
    @Test func headlines() {
        let hot = SampleSource(seed: 1, incident: true).snapshot
        #expect(String(GroupPresentation.panelHeadline(hot).title.characters) == "Claude Code işlemciyi zorluyor.")
        #expect(GroupPresentation.panelHeadline(hot).kicker == "ŞU AN · 4 DAKİKADIR")
        #expect(GroupPresentation.panelHeadline(SampleSource(seed: 1).snapshot).kicker == "ŞU AN")
        #expect(GroupPresentation.panelHeadline(SampleSource(seed: 1).snapshot).lede == "Makine rahat. En yoğun uygulama Brave Browser, %8 ile.")
        #expect(GroupPresentation.cpuHeadline(hot).soft.hasSuffix("çekirdeğin 12,7'si dolu"))
    }
    @Test func emphasisRun() {
        let title = GroupPresentation.panelHeadline(SampleSource(seed: 1, incident: true).snapshot).title
        let emphasized = title.runs.filter { $0.inlinePresentationIntent == .emphasized }.map { String(title[$0.range].characters) }
        #expect(emphasized == ["Claude Code"])
    }
    @Test func ordering() {
        let s = SampleSource(seed: 1).snapshot
        #expect(GroupPresentation.sorted(s.groups, by: .memory).first?.id == "docker")
        #expect(GroupPresentation.related(of: s.groups.first { $0.id == "next-web" }!, in: s.groups)?.id == "claude-acmecorp")
    }
}
