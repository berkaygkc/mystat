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
            return (kicker, title(emph: lead?.name ?? "", rest: " işlemciyi zorluyor."), lead.map { cpuLede($0, s, inc) } ?? "")
        case .memory:
            let grew = zip(inc.culpritIDs, inc.culpritValues).prefix(2).map { "\(name($0)) \($1.dropFirst()) GB" }
            let swap = "Swap \(Fmt.dec1(s.memory.swapGB)) GB'a çıktı."
            guard let top = inc.culpritIDs.first else { return (kicker, AttributedString("Bellek baskısı yükseldi."), swap) }   // büyüyen grup yok
            return (kicker, title(before: "Bellek baskısı yükseldi; en çok ", emph: name(top), rest: " büyüdü."),
                    "Son \(inc.minutes) dakikada \(grew.joined(separator: ", ")) büyüdü. " + swap)
        case .disk:
            var parts: [String] = []
            if let lost = fact(inc, "Son 24 sa") { parts.append("Son 24 saatte \(lost.trimmingCharacters(in: ["−", "-"])) azaldı.") }
            var writer = inc.culpritIDs.first.map { "En çok \(name($0)) yazıyor" } ?? ""
            if s.capabilities.docker, s.docker.running, s.docker.disk.volumesReclaimGB >= 0.05 { writer += (writer.isEmpty ? "Docker'da " : "; Docker'da ") + "\(Fmt.dec1(s.docker.disk.volumesReclaimGB)) GB geri kazanılabilir" }
            if !writer.isEmpty { parts.append(writer + ".") }
            return (kicker, title(before: "Diskte ", emph: "\(Fmt.int(s.disk.freeGB)) GB", rest: " kaldı."), parts.joined(separator: " "))
        case .docker:
            let who = inc.culpritIDs.first ?? "Bir container"
            let inProject = fact(inc, "Proje").flatMap { $0 == "—" ? nil : "\($0) projesinde" }
            switch fact(inc, "Sağlık") {
            case "yeniden başlıyor":
                return (kicker, title(emph: who, rest: " sürekli yeniden başlıyor."),
                        inProject.map { "\($0); Docker onu tekrar tekrar başlatıyor." } ?? "Docker onu tekrar tekrar başlatıyor.")
            case "sağlıksız":
                return (kicker, title(emph: who, rest: " sağlıksız."), inProject.map { "\($0); sağlık denetimi başarısız." } ?? "Sağlık denetimi başarısız.")
            default:
                let othersCalm = !s.docker.containers.contains { $0.name != who && $0.cpuPercent >= 30 }
                return (kicker, title(emph: who, rest: " \(inc.minutes) dakikadır yoğun."),
                        (inProject.map { $0 + " " } ?? "") + "\(inc.culpritValues.first ?? "") CPU kullanıyor." + (othersCalm ? " Diğer container'lar sakin." : ""))
            }
        case .heat:
            let fans = s.capabilities.sensors ? "Fanlar \(Fmt.int(s.system.fanRPM)) dev/dk ile dönüyor. " : ""
            let slow = s.system.thermal == .crit ? "macOS işlemciyi yavaşlatıyor." : "macOS henüz yavaşlatmaya başlamadı."
            let head = s.capabilities.sensors ? title(before: "Çip ısınıyor: ", emph: "\(Fmt.int(s.system.chipTemp))°", rest: ".")
                                              : title(before: "Çip ", emph: "ısınıyor", rest: ".")
            return (kicker, head, fans + slow)
        case .battery:
            let drain = Fmt.pct(s.system.batteryDrain30m ?? 0)
            let left = fact(inc, "Kalan").map { "; bu hızla \($0) yeter" } ?? ""
            let who = inc.culpritIDs.first.map { " En çok \(name($0)) harcıyor." } ?? ""
            return (kicker, title(before: "Pil hızlı eriyor: ", emph: "30 dk'da \(drain)", rest: "."), "Prizde değilsin\(left).\(who)")
        }
    }

    /// Olayın adı verilen olgusu (örnek veride "Son 24 sa", "Kalan" gibi; canlıda yalnızca ölçülebilenler).
    static func fact(_ inc: Incident, _ label: String) -> String? { inc.facts.first { $0.label == label }?.value }

    /// CPU olayı açıklaması: projeli grupta proje, değilse grubun adı; aynı projedeki ikinci sorumlu varsa eşlik cümlesi.
    static func cpuLede(_ lead: ProcessGroup, _ s: Snapshot, _ inc: Incident) -> String {
        let cores = Fmt.dec1(lead.cpuCores)
        var out = lead.folder != nil ? "\(lead.context) projesinde \(cores) çekirdek kullanıyor." : "\(lead.name) \(cores) çekirdek kullanıyor."
        if inc.culpritIDs.count > 1, let second = s.groups.first(where: { $0.id == inc.culpritIDs[1] }),
           second.relatedID == lead.id || lead.relatedID == second.id {
            let server = second.name.hasPrefix("Next.js") ? "Next.js" : second.name
            out += " Aynı projenin \(server) sunucusu da ona eşlik ediyor."
        }
        return out
    }

    /// Grup detayındaki alt süreç satırları: CPU'ya göre en yoğun 5; kalanlar "+ N küçük süreç daha".
    public static func childRows(_ g: ProcessGroup) -> (rows: [ChildProcess], more: Int) {
        let rows = Array(g.children.sorted { $0.cpuCores > $1.cpuCores }.prefix(5))
        return (rows, max(0, g.processCount - rows.count))
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
