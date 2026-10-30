import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

/// Processes are grouped by meaning. The fictional trees mirror the real picture on this machine.
@Suite(.language("tr")) struct ProcessGrouperTests {
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
         // A server started by Claude is a separate group
         p(110, 101, "node", path: "/opt/homebrew/bin/node", args: ["node", "\(proj)/apps/web/node_modules/.bin/next", "dev", "-p", "3011"],
           cwd: "\(proj)/apps/web", root: proj, ageMin: 14),
         p(111, 110, "next-server", path: "/opt/homebrew/bin/node", cwd: "\(proj)/apps/web", root: proj, ageMin: 14),
         // a test runner is not a server
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
        #expect(g?.processCount == 4)                                  // claude, zsh, rg, vitest; the next tree is separate
        #expect(g?.uptime == "2 sa 14 dk" && g?.folder == proj)
    }

    @Test func nextDevIsItsOwnGroupLinkedToClaude() {
        let g = groups(tree)["dev:\(proj)/apps/web:3011"]
        #expect(g?.name == "Next.js dev" && g?.context == "acmecorp/web · :3011" && g?.port == 3011)
        #expect(g?.relatedID == "claude:\(proj)" && g?.isOrphan == false && g?.processCount == 2)
    }

    /// When the launching terminal closes, the server is left to launchd: it is an orphan.
    @Test func orphanDevServer() {
        let r = [p(200, 1, "npm exec next dev -p 3011", path: "/opt/homebrew/bin/node", args: ["npm", "exec", "next", "dev", "-p", "3011"],
                   cwd: "\(proj)/apps/web", root: proj),
                 p(201, 200, "node", path: "/opt/homebrew/bin/node", args: ["node", "\(proj)/apps/web/node_modules/.bin/next", "dev", "-p", "3011"],
                   cwd: "\(proj)/apps/web", root: proj)]
        let g = groups(r, ports: [:])["dev:\(proj)/apps/web:3011"]
        #expect(g?.isOrphan == true && g?.processCount == 2 && g?.port == 3011)   // port comes from an argument
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

    /// Processes we may not inspect appear on a single "macOS" row; their CPU and memory are the remaining value.
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

    /// claude processes that tools like claude-mem start in the background are also Claude Code.
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

    /// A group containing a process that is not the user's cannot be stopped; the macOS row always belongs to the system.
    @Test func foreignMembersMarkGroup() {
        let helper = ProcessRecord(pid: 300, ppid: 1, uid: 0, name: "VPNHelper", path: "/Applications/VPN.app/Contents/MacOS/VPNHelper",
                                   args: [], cwd: nil, start: now, hasTTY: false, cpuTime: 0, footprint: 1 << 20, energy: 0, diskWritten: 0)
        let ui = p(301, 1, "VPN", path: "/Applications/VPN.app/Contents/MacOS/VPN")
        let g = groups(tree + [helper, ui, p(1, 0, "launchd", path: "/sbin/launchd", restricted: true)])
        #expect(g["app:/Applications/VPN.app"]?.foreign == true)
        #expect(g["claude:\(proj)"]?.foreign == false)
        #expect(g["sys:macos"]?.foreign == true)
        #expect(groups(tree, system: (0.4, 2))["sys:macos"]?.foreign == true)   // only the remaining share
    }

    /// acmecorp services run from the root via `tsx services/<name>/src/main.ts`; each one is a separate server group.
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

    /// Two portless servers in the same folder, or two Claude sessions: identities do not collide and stay the same from round to round
    /// (the list and history are keyed by identity). The lowest pid gets the plain identity.
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

    /// Per-process classification is kept across rounds (idle cost); it is recomputed when a pid is reused.
    @Test func classCacheFollowsPidReuse() {
        let cache = ProcessGrouper.ClassCache()
        let first = groups(tsxServices, ports: [:], cache: cache)
        #expect(first.values.filter { $0.name == "tsx" }.count == 2)
        #expect(cache.count == 4)
        #expect(Set(groups(tsxServices, ports: [:], cache: cache).keys) == Set(first.keys))
        // The same pids moved to new processes: plain node scripts
        let reused = [200, 201, 210, 211].map { p($0, 1, "node", path: "/opt/homebrew/bin/node", args: ["node", "x.js"], cwd: proj, ageMin: 1) }
        let after = groups(reused, ports: [:], cache: cache)
        #expect(after.values.allSatisfy { $0.name != "tsx" } && after["proc:node"]?.processCount == 4)
        #expect(cache.count == 4)                                   // old entries were dropped
        #expect(Set(after.keys) == Set(groups(reused, ports: [:]).keys))
    }

    /// loginwindow, Dock and Finder run under the user's uid but are part of the system: they cannot be stopped.
    @Test func systemAppsAreNotStoppable() {
        let lw = p(413, 1, "loginwindow", path: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow")
        let g = groups([lw, p(500, 1, "Brave", path: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser")])
        let login = g["app:/System/Library/CoreServices/loginwindow.app"]
        #expect(login?.name == "loginwindow" && login?.context == "macOS" && login?.foreign == true)
        #expect(g["app:/Applications/Brave Browser.app"]?.foreign == false)
    }


    /// Docker's virtual machine: the kernel truncates the process name to 32 characters, so recognition is done by path (otherwise it fell into "macOS").
    @Test func dockerVMRecognizedByPath() {
        let vm = p(11477, 1, "com.apple.Virtualization.Virtua",
                   path: "/System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine",
                   mem: 10 << 30)
        let g = groups([vm])
        #expect(g["docker:vm"]?.name == "Docker" && g["docker:vm"]?.isDocker == true && g["docker:vm"]?.foreign == false)
        #expect(g["sys:macos"] == nil)
    }
}
