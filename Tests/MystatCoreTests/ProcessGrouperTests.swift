import Foundation
import Testing
@testable import MystatCore

/// Süreçler anlamına göre gruplanır (spec §8). Kurgusal ağaçlar bu makinedeki gerçek görünüme göre.
@Suite struct ProcessGrouperTests {
    let now = Date(timeIntervalSince1970: 1_793_166_318)
    let proj = "/Users/u/Documents/apps/acmecorp"

    func p(_ pid: Int32, _ ppid: Int32, _ name: String, path: String? = nil, args: [String] = [], cwd: String? = nil, root: String? = nil,
           tty: Bool = false, term: String? = nil, ageMin: Double = 30, mem: UInt64 = 100 << 20, restricted: Bool = false) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: ppid, uid: restricted ? 0 : 501, name: name, path: path, args: args, cwd: cwd,
                      start: now.addingTimeInterval(-ageMin * 60), hasTTY: tty, cpuTime: 0, footprint: restricted ? 0 : mem,
                      energy: 0, diskWritten: 0, restricted: restricted, projectRoot: root, terminal: term)
    }

    var tree: [ProcessRecord] {
        [p(100, 50, "claude", path: "/Users/u/.local/bin/claude", args: ["claude"], cwd: proj, root: proj, tty: true, term: "Ghostty", ageMin: 134),
         p(101, 100, "zsh", path: "/bin/zsh", cwd: proj, root: proj),
         p(102, 101, "rg", path: "/opt/homebrew/bin/rg", cwd: proj, root: proj),
         // Claude'un başlattığı sunucu ayrı grup (spec §8/2)
         p(110, 101, "node", path: "/opt/homebrew/bin/node", args: ["node", "\(proj)/apps/web/node_modules/.bin/next", "dev", "-p", "3011"],
           cwd: "\(proj)/apps/web", root: proj, ageMin: 14),
         p(111, 110, "next-server", path: "/opt/homebrew/bin/node", cwd: "\(proj)/apps/web", root: proj, ageMin: 14),
         // test koşucusu sunucu değildir
         p(120, 101, "node", path: "/opt/homebrew/bin/node", args: ["node (vitest)"], cwd: proj, root: proj)]
    }

    func groups(_ r: [ProcessRecord], cores: [Int32: Double] = [:], ports: [Int32: [Int]] = [111: [3011]],
                system: (cores: Double, memoryGB: Double) = (0, 0), cache: ProcessGrouper.ClassCache = .init()) -> [String: ProcessGroup] {
        Dictionary(uniqueKeysWithValues: ProcessGrouper.groups(r, cores: cores, ports: ports, system: system, now: now, home: "/Users/u",
                                                               owner: 501, cache: cache).map { ($0.id, $0) })
    }

    @Test func claudeSessionWithProject() {
        let g = groups(tree)["claude:\(proj)"]
        #expect(g?.name == "Claude Code" && g?.context == "acmecorp" && g?.terminal == "Ghostty")
        #expect(g?.processCount == 4)                                  // claude, zsh, rg, vitest; next ağacı ayrı
        #expect(g?.uptime == "2 sa 14 dk" && g?.folder == proj)
    }

    @Test func nextDevIsItsOwnGroupLinkedToClaude() {
        let g = groups(tree)["dev:\(proj)/apps/web:3011"]
        #expect(g?.name == "Next.js dev" && g?.context == "acmecorp/web · :3011" && g?.port == 3011)
        #expect(g?.relatedID == "claude:\(proj)" && g?.isOrphan == false && g?.processCount == 2)
    }

    /// Başlatan terminal kapanınca sunucu launchd'ye kalır: sahipsiz (§7.3).
    @Test func orphanDevServer() {
        let r = [p(200, 1, "npm exec next dev -p 3011", path: "/opt/homebrew/bin/node", args: ["npm", "exec", "next", "dev", "-p", "3011"],
                   cwd: "\(proj)/apps/web", root: proj),
                 p(201, 200, "node", path: "/opt/homebrew/bin/node", args: ["node", "\(proj)/apps/web/node_modules/.bin/next", "dev", "-p", "3011"],
                   cwd: "\(proj)/apps/web", root: proj)]
        let g = groups(r, ports: [:])["dev:\(proj)/apps/web:3011"]
        #expect(g?.isOrphan == true && g?.processCount == 2 && g?.port == 3011)   // port argümandan
    }

    @Test func appHelpersCollapseIntoTheApp() {
        let app = "/Applications/Brave Browser.app"
        var r = [p(300, 1, "Brave Browser", path: "\(app)/Contents/MacOS/Brave Browser")]
        for i in 0..<13 { r.append(p(301 + Int32(i), 300, "Brave Browser Helper (Renderer)",
                                     path: "\(app)/Contents/Frameworks/Brave Browser Framework.framework/Helpers/Brave Browser Helper (Renderer).app/Contents/MacOS/Brave Browser Helper (Renderer)")) }
        let g = groups(r, cores: [300: 0.2, 305: 0.6])["app:\(app)"]
        #expect(g?.name == "Brave Browser" && g?.context == "14 süreç" && abs((g?.cpuCores ?? 0) - 0.8) < 1e-9)
        #expect(g?.children.count == 14)
    }

    /// İzin verilmeyen süreçler tek "macOS" satırında; CPU ve bellek artık değer (Review Focus #4).
    @Test func systemProcessesAreOneResidualGroup() {
        let r = [p(1, 0, "launchd", path: "/sbin/launchd", restricted: true),
                 p(410, 0, "WindowServer", path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", restricted: true),
                 p(500, 1, "cfprefsd", path: "/usr/sbin/cfprefsd", mem: 1 << 30)]
        let g = groups(r, cores: [500: 0.3], ports: [:], system: (1.2, 5))["sys:macos"]
        #expect(g?.name == "macOS" && g?.context == "sistem süreçleri" && g?.processCount == 3)
        #expect(abs((g?.cpuCores ?? 0) - 1.5) < 1e-9 && abs((g?.memoryGB ?? 0) - 6) < 1e-9)
        #expect(g?.children.map(\.name).contains("WindowServer") == true)
    }

    @Test func dockerVirtualMachine() {
        let g = groups([p(600, 1, "com.apple.Virtualization.VirtualMachine",
                          path: "/System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine")],
                       ports: [:])["docker:vm"]
        #expect(g?.name == "Docker" && g?.context == "sanal makine" && g?.isDocker == true)
    }

    /// claude-mem gibi araçların arka planda başlattığı claude süreçleri de Claude Code'dur.
    @Test func headlessClaudeIsClaudeCode() {
        let g = groups([p(700, 1365, "claude", path: "/Users/u/.local/bin/claude", args: ["claude", "--output-format", "stream-json"],
                          cwd: "/Users/u/.claude-mem", root: nil)], ports: [:])
        #expect(g["claude:/Users/u/.claude-mem"]?.name == "Claude Code")
    }

    @Test func sortedByCPU() {
        let ids = ProcessGrouper.groups(tree, cores: [102: 0.1, 111: 2.0], ports: [111: [3011]], system: (0, 0), now: now, home: "/Users/u", owner: 501).map(\.id)
        #expect(ids.first == "dev:\(proj)/apps/web:3011")
    }

    @Test func uptimeFormat() {
        #expect(Fmt.uptime(14 * 60) == "14 dk")
        #expect(Fmt.uptime(2 * 3600 + 14 * 60) == "2 sa 14 dk")
        #expect(Fmt.uptime(45 * 3600) == "45 sa")
        #expect(Fmt.uptime(3 * 86400) == "3 gün")
        #expect(Fmt.uptime(20) == "1 dk")
    }

    /// Kullanıcının olmayan süreç içeren grup durdurulamaz (spec §7.4); macOS satırı her zaman sistemin.
    @Test func foreignMembersMarkGroup() {
        let helper = ProcessRecord(pid: 300, ppid: 1, uid: 0, name: "VPNHelper", path: "/Applications/VPN.app/Contents/MacOS/VPNHelper",
                                   args: [], cwd: nil, start: now, hasTTY: false, cpuTime: 0, footprint: 1 << 20, energy: 0, diskWritten: 0)
        let ui = p(301, 1, "VPN", path: "/Applications/VPN.app/Contents/MacOS/VPN")
        let g = groups(tree + [helper, ui, p(1, 0, "launchd", path: "/sbin/launchd", restricted: true)])
        #expect(g["app:/Applications/VPN.app"]?.foreign == true)
        #expect(g["claude:\(proj)"]?.foreign == false)
        #expect(g["sys:macos"]?.foreign == true)
        #expect(groups(tree, system: (0.4, 2))["sys:macos"]?.foreign == true)   // yalnızca kalan pay
    }

    /// acmecorp servisleri `tsx services/<ad>/src/main.ts` ile kökten çalışır; her biri ayrı sunucu grubudur.
    var tsxServices: [ProcessRecord] {
        let tsx = "\(proj)/node_modules/.bin/tsx", pre = "\(proj)/node_modules/tsx/dist/preflight.cjs"
        return [p(200, 1, "node", path: "/opt/homebrew/bin/node", args: ["node", tsx, "services/panel/src/main.ts"], cwd: proj, root: proj),
                p(201, 200, "node", path: "/opt/homebrew/bin/node", args: ["node", "--require", pre, "services/panel/src/main.ts"], cwd: proj, root: proj),
                p(210, 1, "node", path: "/opt/homebrew/bin/node", args: ["node", tsx, "services/automation/src/main.ts"], cwd: proj, root: proj),
                p(211, 210, "node", path: "/opt/homebrew/bin/node", args: ["node", "--require", pre, "services/automation/src/main.ts"], cwd: proj, root: proj)]
    }

    @Test func tsxServicesAreOwnDevGroups() {
        let g = groups(tsxServices, ports: [201: [3118]])
        let panel = g.values.first { $0.context == "acmecorp/panel · :3118" }
        #expect(panel?.name == "tsx" && panel?.isOrphan == true && panel?.processCount == 2 && panel?.port == 3118)
        let auto = g.values.first { $0.context == "acmecorp/automation" }
        #expect(auto?.name == "tsx" && auto?.processCount == 2)
        #expect(g["proc:node"] == nil)
        #expect(Set(ProcessGrouper.devServerCandidates(tsxServices)) == [200, 201, 210, 211])
    }

    /// Aynı klasörde portsuz iki sunucu ya da iki Claude oturumu: kimlikler çakışmaz ve turdan tura aynı kalır
    /// (liste ve geçmiş kimlikle tutulur). En küçük pid sade kimliği alır.
    @Test func groupIDsAreUniqueAndStable() {
        let r = [p(300, 1, "node", path: "/opt/homebrew/bin/node", args: ["node", "--watch", "a.js"], cwd: proj, root: proj),
                 p(310, 1, "node", path: "/opt/homebrew/bin/node", args: ["node", "--watch", "b.js"], cwd: proj, root: proj),
                 p(400, 50, "claude", path: "/Users/u/.local/bin/claude", args: ["claude"], cwd: proj, root: proj, tty: true),
                 p(410, 51, "claude", path: "/Users/u/.local/bin/claude", args: ["claude"], cwd: proj, root: proj, tty: true)]
        func ids(_ r: [ProcessRecord]) -> Set<String> {
            Set(ProcessGrouper.groups(r, cores: [:], ports: [:], system: (0, 0), now: now, home: "/Users/u", owner: 501).map(\.id))
        }
        #expect(ids(r) == ["dev:\(proj):0", "dev:\(proj):0#310", "claude:\(proj)", "claude:\(proj)#410"])
        #expect(ids(r.reversed()) == ids(r))
    }

    /// Süreç başına sınıflandırma turlar arasında saklanır (boşta maliyet); pid yeniden kullanılınca yeniden hesaplanır.
    @Test func classCacheFollowsPidReuse() {
        let cache = ProcessGrouper.ClassCache()
        let first = groups(tsxServices, ports: [:], cache: cache)
        #expect(first.values.filter { $0.name == "tsx" }.count == 2)
        #expect(cache.count == 4)
        #expect(Set(groups(tsxServices, ports: [:], cache: cache).keys) == Set(first.keys))
        // Aynı pid'ler yeni süreçlere geçti: düz node betikleri
        let reused = [200, 201, 210, 211].map { p($0, 1, "node", path: "/opt/homebrew/bin/node", args: ["node", "x.js"], cwd: proj, ageMin: 1) }
        let after = groups(reused, ports: [:], cache: cache)
        #expect(after.values.allSatisfy { $0.name != "tsx" } && after["proc:node"]?.processCount == 4)
        #expect(cache.count == 4)                                   // eski kayıtlar atıldı
        #expect(Set(after.keys) == Set(groups(reused, ports: [:]).keys))
    }

    /// loginwindow, Dock, Finder kullanıcının uid'iyle çalışır ama sistemin parçasıdır: durdurulamaz.
    @Test func systemAppsAreNotStoppable() {
        let lw = p(413, 1, "loginwindow", path: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow")
        let g = groups([lw, p(500, 1, "Brave", path: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser")])
        let login = g["app:/System/Library/CoreServices/loginwindow.app"]
        #expect(login?.name == "loginwindow" && login?.context == "macOS" && login?.foreign == true)
        #expect(g["app:/Applications/Brave Browser.app"]?.foreign == false)
    }

}
