import Foundation

/// Mockup'tan (docs/mockups/monitor.html: GROUPS, CONTAINERS, TREE) birebir aktarılan örnek veri.
enum SampleData {
    struct G {
        let id, name, ctx: String
        let cpu: (Double, Double)      // (sakin, patlama) çekirdek
        let ram: Double
        let net: (Double, Double)
        let up: String
        var dir: String? = nil, term: String? = nil, port: Int? = nil
        var orphan = false, related: String? = nil, docker = false
        let n: Int
        let kids: [(String, Double, Double)]
    }

    static let groups: [G] = [
        G(id: "claude-acmecorp", name: "Claude Code", ctx: "acmecorp", cpu: (0.28, 4.2), ram: 1.1, net: (0.2, 0.4), up: "2 sa 14 dk",
          dir: "~/Documents/apps/acmecorp", term: "Ghostty · 2. sekme", related: "next-web", n: 9,
          kids: [("claude", 0.25, 3.1), ("node · MCP notes", 0.05, 0.4), ("bash", 0.03, 0.3), ("rg", 0.02, 0.2), ("node · MCP calendar", 0.02, 0.2)]),
        G(id: "next-web", name: "Next.js dev", ctx: "acmecorp/web · :3011", cpu: (0.1, 3.1), ram: 2.4, net: (0.01, 0.02), up: "14 dk",
          dir: "~/Documents/apps/acmecorp/apps/web", port: 3011, orphan: true, related: "claude-acmecorp", n: 3,
          kids: [("next-server (v16.2.10)", 0.08, 2.9), ("node · next dev", 0.01, 0.1), ("npm exec next dev", 0.01, 0.1)]),
        G(id: "docker", name: "Docker", ctx: "deploy · 15 container", cpu: (0.03, 0.9), ram: 10.2, net: (9.8, 9.8), up: "45 sa", docker: true, n: 15,
          kids: [("acmecorp-verifier", 0.004, 0.62), ("temporal", 0.006, 0.12), ("app-pg", 0.002, 0.08), ("grafana", 0.003, 0.05), ("loki", 0.004, 0.03)]),
        G(id: "brave", name: "Brave Browser", ctx: "14 süreç", cpu: (0.35, 0.42), ram: 2.1, net: (4.1, 4.1), up: "3 gün", n: 14,
          kids: [("GPU süreci", 0.12, 0.14), ("Brave Browser", 0.1, 0.12), ("Sekme · Linear", 0.06, 0.07), ("Sekme · GitHub", 0.04, 0.05)]),
        G(id: "windowserver", name: "WindowServer", ctx: "macOS", cpu: (0.18, 0.3), ram: 1.5, net: (0, 0), up: "3 gün", n: 1, kids: []),
        G(id: "claude-mystat", name: "Claude Code", ctx: "mystat", cpu: (0.12, 0.2), ram: 0.6, net: (0.1, 0.1), up: "1 sa 02 dk",
          dir: "~/Documents/hobby-projects/mystat", term: "Ghostty · 1. sekme", n: 4,
          kids: [("claude", 0.1, 0.15), ("node · MCP git", 0.02, 0.05)]),
        G(id: "datagrip", name: "DataGrip", ctx: "", cpu: (0.03, 0.03), ram: 2.5, net: (0, 0), up: "5 sa", n: 1, kids: []),
        G(id: "next-panel", name: "Next.js", ctx: "acmecorp/panel · :3118", cpu: (0.02, 0.05), ram: 0.4, net: (0, 0), up: "1 sa 20 dk",
          dir: "~/Documents/apps/acmecorp/apps/panel", port: 3118, n: 2, kids: [("next-server (v16.2.10)", 0.02, 0.05)]),
        G(id: "spark", name: "Spark", ctx: "", cpu: (0.02, 0.02), ram: 0.5, net: (0.2, 0.2), up: "3 gün", n: 2, kids: []),
    ]

    /// (ad, image, (sakin, patlama) CPU %, bellek MB, sağlık kontrolü var mı)
    static let containers: [(String, String, (Double, Double), Double, Bool)] = [
        ("acmecorp-verifier", "acmecorp-verifier:dev", (0.4, 62), 412, true),
        ("temporal", "temporalio/auto-setup:1.25", (0.6, 12), 286, false),
        ("app-pg", "postgres:17-alpine", (0.2, 8), 148, false),
        ("grafana", "grafana/grafana:11.3.0", (0.3, 5), 164, false),
        ("loki", "grafana/loki:3.2.0", (0.4, 3), 210, false),
        ("temporal-pg", "postgres:17-alpine", (0.3, 3), 132, false),
        ("vector", "timberio/vector:0.39.0-alpine", (0.5, 2), 74, false),
        ("authgate", "quay.io/authgate/authgate:25", (0.2, 1.2), 512, false),
        ("acmecorp-docs-service", "acmecorp-docs-service:dev", (0.1, 1), 188, true),
        ("event-pg", "postgres:17-alpine", (0.1, 1), 96, false),
        ("redis", "redis:7-alpine", (0.2, 0.6), 18, false),
        ("minio", "minio/minio", (0.1, 0.5), 120, false),
        ("users-archive-pg", "postgres:17-alpine", (0.1, 0.4), 88, false),
        ("nats", "nats:2.10", (0.1, 0.3), 22, false),
        ("temporal-ui", "temporalio/ui:2.31.0", (0.0, 0.2), 46, false),
    ]

    static func makeTree() -> DiskNode {
        typealias N = DiskNode
        return N("Ev", 236, [
            N("Library", 96, [
                N("Containers", 41, [
                    N("Docker", 27, [N("Docker.raw", 26.6, file: true, docker: true), N("Diğer", 0.4, file: true)]),
                    N("Telegram", 4), N("Spark", 3.2), N("Diğer", 6.8)]),
                N("Application Support", 28, [N("JetBrains", 7.4), N("Code", 6.2), N("BraveSoftware", 5.1), N("Diğer", 9.3)]),
                N("Caches", 14, [N("Homebrew", 4.1), N("pnpm", 3.8), N("BraveSoftware", 2.2), N("Diğer", 3.9)]),
                N("Developer", 9, [N("DerivedData", 6.4), N("CoreSimulator", 2.6)]),
                N("Diğer", 4)]),
            N("Documents", 52, [
                N("apps", 31, [
                    N("acmecorp", 24, [N("node_modules", 11.2), N(".next", 4.1), N("apps", 6.3), N("Diğer", 2.4)]),
                    N("Diğer", 7)]),
                N("hobby-projects", 12, [N("node_modules (8 proje)", 7.8), N("Diğer", 4.2)]),
                N("Diğer", 9)]),
            N("Downloads", 18, [N("Xcode_26.2.xip", 9.5, file: true), N("Ekran Kayıtları", 5.2), N("Diğer", 3.3)]),
            N("Movies", 9), N("Pictures", 6), N(".npm", 4.2), N(".cache", 3.1), N("Diğer", 46.7),
        ])
    }

    static let netDetails = [
        Fact("Bant", "5 GHz · kanal 44"), Fact("Bağlantı hızı", "1.201 Mb/sn"), Fact("Sinyal", "Çok iyi · −48 dBm"),
        Fact("Yerel IP", "192.168.1.42"), Fact("Yönlendirici", "192.168.1.1"), Fact("DNS", "1.1.1.1, 8.8.8.8"), Fact("Arayüz", "en0"),
    ]
}
