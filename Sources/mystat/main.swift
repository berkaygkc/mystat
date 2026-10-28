import AppKit

#if DEBUG
if CommandLine.arguments.contains("--scan-home") {
    MainActor.assumeIsolated { DiskCheck.run() }
}
#endif

if CommandLine.arguments.contains("--snapshot") {
    MainActor.assumeIsolated { SnapshotMode.run(CommandLine.arguments) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
