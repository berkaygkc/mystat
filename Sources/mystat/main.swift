import AppKit

if CommandLine.arguments.contains("--snapshot") {
    MainActor.assumeIsolated { SnapshotMode.run(CommandLine.arguments) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
