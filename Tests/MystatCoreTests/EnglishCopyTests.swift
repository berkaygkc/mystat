import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

/// İngilizce metinler: Türkçe testlerin karşılıkları, birer örnekle.
@MainActor @Suite(.language("en")) struct EnglishCopyTests {
    @Test func menubarLabels() {
        let cal = Calendar.trTest, now = Date()
        let calm = StatusBlockLayout.model(SampleSource(seed: 1).snapshot, now: now, calendar: cal)
        #expect(calm.metrics.map(\.label) == ["CPU", "RAM", "DISK"])
        let a = { (k: IncidentKind) in StatusBlockLayout.model(SampleSource(seed: 1, incident: true, kind: k).snapshot, now: now, calendar: cal).alert }
        #expect(a(.heat)?.label == "TEMP"); #expect(a(.battery) == StatusMetric(label: "BATT", value: "−25%", level: .warn))
        #expect(a(.docker)?.label == "DOCKER")   // değer örnek veriden (Task 5)
    }

    @Test func calmPanel() {
        let s = SampleSource(seed: 1).snapshot
        let h = GroupPresentation.panelHeadline(s)
        #expect(h.kicker == "NOW"); #expect(String(h.title.characters) == "All good.")
        #expect(h.lede == "The machine is relaxed. The busiest app is Brave Browser, at 8%.")
        let cells = PanelPresentation.cells(s)
        #expect(cells.map(\.label) == ["CPU", "Memory", "Disk", "Network", "Docker", "System"])
        #expect(cells[0].sub == "14 cores, calm")
        #expect(MonitorPresentation.sectionTitles["net"] == "Network")
    }

    @Test func cpuIncident() {
        let s = SampleSource(seed: 1, incident: true).snapshot
        let h = GroupPresentation.panelHeadline(s)
        #expect(String(h.title.characters) == "Claude Code is straining the CPU.")
        #expect(h.kicker == "NOW · FOR 4 MINUTES")
        #expect(MonitorPresentation.sideIncidentText(s) == "Claude Code is straining the CPU")
        #expect(MonitorPresentation.inspectTitle(section: "cpu") == "Inspect CPU")
        let emph = h.title.runs.filter { $0.inlinePresentationIntent == .emphasized }.map { String(h.title[$0.range].characters) }
        #expect(emph == ["Claude Code"])
    }

    @Test func incidentSentences() {
        var s = SampleSource(seed: 1, incident: true, kind: .battery).snapshot
        s.incident = Incident(kind: .battery, level: .warn, startedAt: "10:00", minutes: 9, peakPercent: 0, culpritIDs: [], culpritValues: [],
                              culpritUnit: "W", facts: [])
        #expect(MonitorPresentation.incidentSentence(s) == "Battery dropped 25% in 9 minutes.")
        s.incident = Incident(kind: .memory, level: .crit, startedAt: "10:00", minutes: 1, peakPercent: 0, culpritIDs: [], culpritValues: [],
                              culpritUnit: "GB", facts: [])
        #expect(MonitorPresentation.incidentSentence(s) == "Memory pressure has been high for 1 minute.")
    }

    @Test func cpuHeadlineAndCores() {
        var s = SampleSource(seed: 1).snapshot
        #expect(GroupPresentation.cpuHeadline(s).title == "CPU is relaxed.")
        s.cpu.percent = 91
        #expect(GroupPresentation.cpuHeadline(s).soft == " · 12.7 of 14 cores busy")
        #expect(MonitorPresentation.coreLabels(count: 14, machine: nil).note == "10 performance · 4 efficiency")
        #expect(MonitorPresentation.coreLabels(count: 14, machine: nil).labels.last == "E4")
    }
}

/// Örnek veri ve ölçüm tarafında üretilen metinler, İngilizce.
@MainActor @Suite(.language("en")) struct EnglishSampleTests {
    @Test func sampleIncidentAndMenubar() {
        let docker = SampleSource(seed: 1, incident: true, kind: .docker).snapshot
        #expect(StatusBlockLayout.alert(docker) == StatusMetric(label: "DOCKER", value: "62%", level: .warn))
        #expect(docker.incident?.facts.map(\.label) == ["Project", "Duration", "Health"])
        #expect(docker.incident?.facts.last?.value == "healthy")
        let cpu = SampleSource(seed: 1, incident: true).snapshot
        #expect(cpu.incident?.facts.first.map { "\($0.label) \($0.value)" } == "Started 08:41")
        #expect(cpu.incident?.facts[1].value == "97%"); #expect(cpu.incident?.culpritValues.first == "4.2")
        #expect(cpu.incident?.culpritUnit == "cores")
        let bat = SampleSource(seed: 1, incident: true, kind: .battery).snapshot
        #expect(MonitorPresentation.incidentSentence(bat) == "Battery dropped 25% in 30 minutes; at this rate it lasts 1 h 10 min.")
    }

    @Test func sampleSuggestionsAndGroups() {
        let s = SampleSource(seed: 1).snapshot
        #expect(s.suggestions.map(\.title).last == "9.5 GB Xcode archive in Downloads")
        #expect(s.suggestions.last?.detail == "Not opened for 3 weeks")
        #expect(s.groups.first { $0.id == "brave" }?.context == "14 processes")
        #expect(s.groups.first { $0.id == "docker" }?.context == "deploy · 15 containers")
        #expect(s.groups.first { $0.id == "claude-mystat" }?.uptime == "1 h 02 min")
        #expect(SectionText.system(s).lede == "Chip 48°, fans stopped. Plugged in, battery full and healthy.")
        #expect(s.net.details.first?.label == "Band")
    }

    @Test func timeAndMachine() {
        #expect(TimeRange.h24.title == "24 h"); #expect(TimeRange.d7.axisLabels == ["7 days ago", "3 days", "now"])
        let m = MachineInfo(model: "MacBook Pro", chip: "M4 Pro", pCores: 10, eCores: 4, memoryGB: 48, boot: Date().addingTimeInterval(-3 * 86_400 - 60))
        #expect(m.footer(now: Date()).hasSuffix("14 cores · 48 GB · up 3 days"))
        #expect(StopOutcome.foreignReason.hasPrefix("Some of this group's processes"))
    }

    @Test func sampleDiskNames() {
        let t = SampleSource(seed: 1).diskTree
        #expect(t.node(at: ["Downloads"])?.children?.map(\.displayName) == ["Xcode_26.2.xip", "Screen Recordings", "Other"])
        #expect(t.node(at: ["Other"])?.kind == .other)
        #expect(DiskNode.display(DiskNode.smallFilesName) == "Other")
    }
}
