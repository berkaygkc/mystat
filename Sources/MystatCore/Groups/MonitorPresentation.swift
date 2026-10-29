import Foundation

/// Monitör penceresine özgü metin ve eşlemeler.
public enum MonitorPresentation {
    /// Kenar menüsündeki canlı değer (mockup'taki `navVal`).
    public static func navValue(_ section: String, _ s: Snapshot) -> (text: String, level: Level) {
        switch section {
        case "cpu": (Fmt.pct(s.cpu.percent), Thresholds.cpuTotal(s.cpu.percent))
        case "mem": (Fmt.pct(s.memory.percent), s.memory.pressureLevel)
        case "disk": (Fmt.pct(s.disk.percent), Thresholds.diskFree(s.disk.freeGB))
        case "net": ("↓" + Fmt.rate(s.net.downMBps), .ok)
        case "docker": s.capabilities.docker && s.docker.running ? (String(s.docker.containers.count), s.incident?.kind == .docker ? s.incident!.level : .ok) : ("—", .ok)
        case "sys": (s.capabilities.sensors ? Fmt.int(s.system.chipTemp) + "°" : "", s.system.batteryDrain30m != nil ? .warn : s.system.thermal)
        default: ("", .ok)
        }
    }

    /// Kenar menüsündeki olay kartı: panel başlığı, sondaki nokta olmadan (mockup `.side-inc .t`).
    public static func sideIncidentText(_ s: Snapshot) -> String {
        let t = String(GroupPresentation.panelHeadline(s).title.characters)
        return t.hasSuffix(".") ? String(t.dropLast()) : t
    }

    /// Olay kartının tek cümlelik özeti.
    public static func incidentSentence(_ s: Snapshot) -> String {
        guard let inc = s.incident else { return "" }
        let m = inc.minutes
        switch inc.kind {
        case .cpu:
            let lead = s.groups.first { $0.id == inc.culpritIDs.first }
            guard s.cpu.percent >= 70 else {   // toplam düşük, tek grup yüksek
                return "\(lead?.name ?? "Bir grup") \(m) dakikadır \(Fmt.dec1(lead?.cpuCores ?? 0)) çekirdek kullanıyor."
            }
            let floor10 = String(Int(s.cpu.percent / 10) * 10)
            let source = lead.map { $0.folder != nil ? " Yükün çoğu \($0.context) projesinden geliyor." : " En çok \($0.name) yüklüyor." } ?? ""
            return "İşlemci \(m) dakikadır %\(floor10)\(TurkishSuffix.genitive(after: floor10)) üzerinde.\(source)"
        case .memory:
            let who = s.groups.first { $0.id == inc.culpritIDs.first }?.name
            return "Bellek baskısı \(m) dakikadır \(PanelPresentation.pressureWord(inc.level))." + (who.map { " En çok \($0) büyüyor." } ?? "")
        case .disk:
            let lost = GroupPresentation.fact(inc, "Son 24 sa").map { "; son 24 saatte \($0.trimmingCharacters(in: ["−", "-"])) azaldı" } ?? ""
            return "Diskte \(Fmt.int(s.disk.freeGB)) GB kaldı\(lost)."
        case .docker:
            let who = inc.culpritIDs.first ?? "Bir container"
            switch GroupPresentation.fact(inc, "Sağlık") {
            case "yeniden başlıyor": return "\(who) \(m) dakikadır yeniden başlıyor."
            case "sağlıksız": return "\(who) \(m) dakikadır sağlıksız."
            default: return "\(who) \(m) dakikadır \(inc.culpritValues.first ?? "") CPU kullanıyor."
            }
        case .heat:
            return s.capabilities.sensors && s.system.fanCount > 0 && s.system.fanRPM > 0 ? "Çip \(m) dakikadır ısınıyor; fanlar \(Fmt.int(s.system.fanRPM)) dev/dk ile dönüyor."
                                          : "Çip \(m) dakikadır ısınıyor; termal durum \(s.system.thermal.thermalWord.lowercased(with: Fmt.locale))."
        case .battery:
            let left = GroupPresentation.fact(inc, "Kalan").map { "; bu hızla \($0) yeter" } ?? ""
            return "Pil \(m) dakikada \(Fmt.pct(s.system.batteryDrain30m ?? 0)) eridi\(left)."
        }
    }

    /// Olayın detayının bulunduğu bölüm.
    public static func section(for kind: IncidentKind) -> String {
        switch kind { case .cpu: "cpu"; case .memory: "mem"; case .disk: "disk"; case .docker: "docker"; case .heat, .battery: "sys" }
    }

    /// Olay kartındaki küçük grafiğin serisi.
    public static func seriesKey(for kind: IncidentKind) -> SeriesKey {
        switch kind { case .cpu: .cpu; case .memory: .memPressure; case .disk: .diskWrite; case .docker: .dockerCPU; case .heat: .temp; case .battery: .power }
    }

    public static let sectionTitles: [String: String] = [
        "overview": "Genel Bakış", "cpu": "İşlemci", "mem": "Bellek", "disk": "Disk", "net": "Ağ", "docker": "Docker", "sys": "Sistem",
    ]

    /// "İşlemci'de incele", "Bellek'te incele" … (ünsüz yumuşaması/sertleşmesi elle).
    public static func inspectTitle(section: String) -> String {
        let locative = ["cpu": "İşlemci'de", "mem": "Bellek'te", "disk": "Disk'te", "net": "Ağ'da", "docker": "Docker'da", "sys": "Sistem'de"]
        return (locative[section] ?? "Monitörde") + " incele"
    }
}

extension MonitorPresentation {
    /// Genel Bakış başlığının altındaki paragraf (mockup `secOverview`).
    public static func overviewLede(_ s: Snapshot) -> String {
        guard let inc = s.incident else {
            let docker = s.capabilities.docker && s.docker.running ? ", Docker \(s.docker.containers.count) container ile sessizce ayakta" : ""
            return "Makine rahat. En yoğun uygulama \(s.calmTop.name)\(docker). Diskte \(Fmt.int(s.disk.freeGB)) GB boş yer var."
        }
        guard inc.kind == .cpu, let lead = s.groups.first(where: { $0.id == inc.culpritIDs.first }) else {
            return GroupPresentation.panelHeadline(s).lede
        }
        // Olgular verilerden: eşlik eden sunucu yalnızca olayda ilişkiliyse, "normal" yalnızca bellek ve disk sakinse.
        var t = GroupPresentation.cpuLede(lead, s, inc).replacingOccurrences(of: ". Aynı projenin", with: "; aynı projenin")
        if s.memory.pressureLevel == .ok, Thresholds.diskFree(s.disk.freeGB) == .ok { t += " Bellek, disk ve ağ normal." }
        return t
    }

    /// Çekirdek etiketleri: önce performans (P), sonra verimlilik (V). Canlı seri bu sırada gelir (`SnapshotBuilder`);
    /// makine bilgisi yoksa (örnek veri) mockup'taki 10 + 4.
    public static func coreLabels(count: Int, machine: MachineInfo?) -> (labels: [String], note: String) {
        let p = machine.map { $0.pCores + $0.eCores == count ? $0.pCores : count } ?? Swift.min(10, count)
        let e = count - p
        return ((0..<count).map { $0 < p ? "P\($0 + 1)" : "V\($0 - p + 1)" }, e > 0 ? "\(p) performans · \(e) verimlilik" : "\(p) çekirdek")
    }

    public static let cpuCalmLede = "Son 10 dakikada hiçbir uygulama bir çekirdekten fazlasını uzun süre kullanmadı."
}
