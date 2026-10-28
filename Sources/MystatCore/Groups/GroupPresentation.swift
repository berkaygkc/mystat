import Foundation

public enum GroupMetric: Hashable, Sendable { case cpu, memory, network }

/// Grup listeleri, başlık cümleleri ve "Teşhisi kopyala" metni.
public enum GroupPresentation {
    public static func value(_ g: ProcessGroup, _ m: GroupMetric) -> Double {
        switch m { case .cpu: g.cpuCores; case .memory: g.memoryGB; case .network: g.netMBps }
    }

    public static func sorted(_ groups: [ProcessGroup], by m: GroupMetric) -> [ProcessGroup] {
        groups.sorted { value($0, m) > value($1, m) }
    }

    public static func related(of g: ProcessGroup, in all: [ProcessGroup]) -> ProcessGroup? {
        g.relatedID.flatMap { id in all.first { $0.id == id } }
    }

    /// Panoya kopyalanan teşhis. Saatten sonra ek kullanılmaz (sesli uyumu rakama bağlı).
    public static func diagnosis(_ g: ProcessGroup, incident: Incident?) -> String {
        var lines = ["\(g.name)\(g.context.isEmpty ? "" : " (\(g.context))") şu an \(Fmt.cores(g.cpuCores)) çekirdek CPU ve \(Fmt.mem(g.memoryGB)) bellek kullanıyor."]
        if let inc = incident, inc.kind == .cpu, g.cpuCores > 1 {
            lines.append("Son \(inc.minutes) dakikadır yüksek (başlangıç \(inc.startedAt), toplam CPU zirvesi \(Fmt.pct(inc.peakPercent))).")
        }
        lines.append("Açık kalma süresi: \(g.uptime). Süreç sayısı: \(g.processCount).")
        if let f = g.folder { lines.append("Klasör: \(f)") }
        if let p = g.port { lines.append("Port: \(p)") }
        if !g.children.isEmpty {
            let top = g.children.prefix(3).map { "\($0.name) \(Fmt.cores($0.cpuCores))" }.joined(separator: ", ")
            lines.append("En yoğun alt süreçler: \(top).")
        }
        if g.isOrphan { lines.append("Not: başlatan terminal kapanmış, süreç sahipsiz çalışıyor.") }
        return lines.joined(separator: "\n")
    }

    /// Panel ve Genel Bakış başlığı. Vurgulu kısım `.emphasized` ile işaretlenir; arayüz onu kırmızı/turuncu boyar.
    public static func panelHeadline(_ s: Snapshot) -> (kicker: String, title: AttributedString, lede: String) {
        guard let inc = s.incident else {
            return ("ŞU AN", AttributedString("Her şey yolunda."),
                    "Makine rahat. En yoğun uygulama \(s.calmTop.name), %\(s.calmTop.percent) ile.")
        }
        let kicker = "ŞU AN · \(inc.minutes) DAKİKADIR"
        let name = { (id: String) in s.groups.first { $0.id == id }?.name ?? id }
        switch inc.kind {
        case .cpu:
            let lead = s.groups.first { $0.id == inc.culpritIDs.first }
            return (kicker, title(emph: lead?.name ?? "", rest: " işlemciyi zorluyor."),
                    "\(lead?.context ?? "") projesinde \(Fmt.dec1(lead?.cpuCores ?? 0)) çekirdek kullanıyor. Aynı projenin Next.js sunucusu da ona eşlik ediyor.")
        case .memory:
            return (kicker, title(before: "Bellek baskısı yükseldi; en çok ", emph: name(inc.culpritIDs[0]), rest: " büyüdü."),
                    "Son \(inc.minutes) dakikada \(name(inc.culpritIDs[0])) \(inc.culpritValues[0].dropFirst()) GB, \(name(inc.culpritIDs[1])) \(inc.culpritValues[1].dropFirst()) GB büyüdü. Swap \(Fmt.dec1(s.memory.swapGB)) GB'a çıktı.")
        case .disk:
            return (kicker, title(before: "Diskte ", emph: "\(Fmt.int(s.disk.freeGB)) GB", rest: " kaldı."),
                    "Son 24 saatte 14 GB azaldı. En çok Docker yazıyor; Docker'da \(Fmt.dec1(s.docker.disk.volumesReclaimGB)) GB geri kazanılabilir.")
        case .docker:
            return (kicker, title(emph: inc.culpritIDs[0], rest: " \(inc.minutes) dakikadır yoğun."),
                    "\(s.docker.project) projesinde \(inc.culpritValues[0]) CPU kullanıyor. Diğer container'lar sakin.")
        case .heat:
            return (kicker, title(before: "Çip ısınıyor: ", emph: "\(Fmt.int(s.system.chipTemp))°", rest: "."),
                    "Fanlar \(Fmt.int(s.system.fanRPM)) dev/dk ile dönüyor. macOS henüz yavaşlatmaya başlamadı.")
        case .battery:
            let drain = Fmt.pct(s.system.batteryDrain30m ?? 0)
            return (kicker, title(before: "Pil hızlı eriyor: ", emph: "30 dk'da \(drain)", rest: "."),
                    "Prizde değilsin; bu hızla 1 sa 10 dk yeter. En çok \(name(inc.culpritIDs[0])) harcıyor.")
        }
    }

    /// İşlemci bölümü başlığı: ("%91", " · 14 çekirdeğin 12,7'si dolu") ya da ("İşlemci rahat.", "%14").
    public static func cpuHeadline(_ s: Snapshot) -> (title: String, soft: String) {
        let pct = Fmt.pct(s.cpu.percent)
        guard s.cpu.percent >= 70 else { return ("İşlemci rahat.", pct) }
        let total = s.cpu.cores.count
        let used = Fmt.dec1(s.cpu.percent / 100 * Double(total))
        return (pct, " · \(total) çekirdeğin \(used)\(TurkishSuffix.possessive3(after: used)) dolu")
    }

    private static func title(before: String = "", emph: String, rest: String) -> AttributedString {
        var e = AttributedString(emph)
        e.inlinePresentationIntent = .emphasized
        return AttributedString(before) + e + AttributedString(rest)
    }
}
