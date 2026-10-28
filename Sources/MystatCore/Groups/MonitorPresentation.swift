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
        case "docker": (String(s.docker.containers.count), s.incident?.kind == .docker ? s.incident!.level : .ok)
        case "sys": (Fmt.int(s.system.chipTemp) + "°", s.system.batteryDrain30m != nil ? .warn : s.system.thermal)
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
            let project = s.groups.first { $0.id == inc.culpritIDs.first }?.context ?? ""
            return "İşlemci \(m) dakikadır %90'ın üzerinde. Yükün çoğu \(project) projesinden geliyor."
        case .memory:
            let who = s.groups.first { $0.id == inc.culpritIDs.first }?.name ?? ""
            return "Bellek baskısı \(m) dakikadır yüksek. En çok \(who) büyüyor."
        case .disk:
            return "Diskte \(Fmt.int(s.disk.freeGB)) GB kaldı; son 24 saatte 14 GB azaldı."
        case .docker:
            return "\(inc.culpritIDs.first ?? "") \(m) dakikadır \(inc.culpritValues.first ?? "") CPU kullanıyor."
        case .heat:
            return "Çip \(m) dakikadır ısınıyor; fanlar \(Fmt.int(s.system.fanRPM)) dev/dk ile dönüyor."
        case .battery:
            return "Pil \(m) dakikada \(Fmt.pct(s.system.batteryDrain30m ?? 0)) eridi; bu hızla 1 sa 10 dk yeter."
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
            return "Makine rahat. En yoğun uygulama \(s.calmTop.name), Docker \(s.docker.containers.count) container ile sessizce ayakta. Diskte \(Fmt.int(s.disk.freeGB)) GB boş yer var."
        }
        guard inc.kind == .cpu, let lead = s.groups.first(where: { $0.id == inc.culpritIDs.first }) else {
            return GroupPresentation.panelHeadline(s).lede
        }
        return "\(lead.context) projesinde \(Fmt.dec1(lead.cpuCores)) çekirdek kullanıyor; aynı projenin Next.js sunucusu da ona eşlik ediyor. Bellek, disk ve ağ normal."
    }

    public static let cpuCalmLede = "Son 10 dakikada hiçbir uygulama bir çekirdekten fazlasını uzun süre kullanmadı."
}
