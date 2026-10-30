# Contributing

Thanks for your interest in mystat! Bug reports, translations and pull requests are welcome.

## Building and testing

```sh
swift build
swift test
scripts/make-app.sh install   # build, sign and run the app bundle
```

Some tests read real hardware (SMC sensors, Wi‑Fi, processes), so run them on a Mac, not in a VM.

## How the code is organized

| Target | What it does |
|---|---|
| `MystatCore` | Models, formatting, localization and every piece of text logic: snapshots, incidents, process grouping, sample data. No system calls. |
| `MystatProbes` | Reads the system: CPU ticks, memory, processes, disks, network, SMC sensors, battery, Docker's socket API. |
| `MystatLive` | Turns probe readings into snapshots on a 2-second schedule, keeps history, runs the disk scanner and Docker poller. |
| `MystatUI` | SwiftUI views: the panel and the monitor window. |
| `mystat` | The app: menu bar item, windows, snapshot mode for screenshots. |

Run `.build/debug/mystat --snapshot panel --lang en --out panel.png` to render a screen with sample data. `tools/lang-gallery.sh <lang>` renders all of them.

## Guidelines

- **Keep it light.** mystat runs all day; idle cost matters. Measure before and after if you touch sampling or drawing.
- **No root, no helper tools.** Everything runs as a normal user process.
- **User-visible text goes in `Locales/`**, never in code. See [Translating mystat](Locales/README.md).
- **Code comments are in English.**
- **Before opening a pull request**, make sure `swift test` passes. That includes the locale and repository checks.
