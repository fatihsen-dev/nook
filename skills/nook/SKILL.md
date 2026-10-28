---
name: nook
description: Use when building a nooklet for Nook, the macOS manager for small native desktop apps (widgets, mini docks, now-playing panels, monitors). Covers the nooklet layout, the NookKit API and the nookctl build-run-logs loop.
---

# Building nooklets for Nook

Nook (https://nook.fatihsen.dev) runs small native macOS apps called **nooklets**. A nooklet is a plain Swift package whose executable links **NookKit**. Nook builds it in release mode, installs the binary and registers it with launchd, so it keeps running after the Nook window closes, starts at login and restarts after a crash. macOS 14 or later, Swift 6 toolchain.

Nook draws nothing around a nooklet. The UI is ordinary SwiftUI or AppKit, and features come from ordinary macOS APIs. NookKit has no feature services (no now-playing, battery or weather API); do not invent any.

## Workflow

Use `nookctl`, the command-line tool shipped inside Nook.app (installed to `~/.local/bin/nookctl` by the installer; otherwise it is at `/Applications/Nook.app/Contents/MacOS/nookctl` or `~/Applications/Nook.app/Contents/MacOS/nookctl`).

1. Create: `nookctl new <folder> --name "Battery Ring" [--id com.you.battery-ring] [--run]`. It creates the folder if needed, writes `nook.json`, `Package.swift`, `.gitignore` and `Sources/app.swift`, and adds it to the library; `--run` also builds and starts it. Without `--id`, the id is derived from the user name and the nooklet name.
2. Edit `Sources/app.swift` (and add more files under `Sources/` freely).
3. Check: `nookctl build .` compiles in release mode without installing or starting (first build of a package takes ~10 s, later ones 1-3 s). Failures print one `<file>:<line>:<column>: error: <message>` line per error, then `build failed for <id> (<seconds> s)`, and exit with status 1; when no error line can be parsed (linker errors) the whole compiler log is printed instead. `diagnostics` holds errors only; warnings appear only in the log. `--json` prints `{id, success, durationSeconds, diagnostics: [{file, line, column, message}], log}`, with `log` present only on failure.
4. Run: `nookctl run .` builds, installs and starts it, or restarts it with the new build. Output and `--json` are the same as `build`; a failed build exits 1 and leaves the previously running version untouched.
5. Verify: `nookctl logs . --lines 50` (add `--follow` to stream until interrupted). `nookctl list --json` prints an array of `{id, name, directory, status: running|stopped|broken, pid, memoryBytes, lastBuildSucceeded, problem}`; `null` fields are omitted.
6. `nookctl stop .` stops it; `nookctl remove .` stops it and removes it from the library but never deletes the folder.

`<nooklet>` is the id from `nook.json` or the nooklet's folder (`.` inside it); `build`, `run`, `stop` and `logs` only work on nooklets in the library, so add an existing folder first with `nookctl add <folder>`. `nookctl` does not need the Nook app to be running; an open Nook window picks up its changes within a few seconds. `nookctl help` (or `--help` after any command) prints the full usage. Exit status: 0 success, 1 failure (including a failed build), 64 wrong usage.

## What Nook does with a nooklet

- `run` copies the built executable (and any `*.bundle` resources) to `~/Library/Application Support/Nook/bin/<id>/` and registers a launchd agent `dev.nook.nooklet.<id>`: it starts now and at every login, and is restarted if it crashes or exits with a non-zero status. A clean exit (status 0) is not restarted.
- `stop` unregisters the agent, so a stopped nooklet stays stopped across logins until the next `run`.
- `remove` stops it and deletes the installed binary, the agent, the log and the last build report. It never touches the source folder. The saved panel position survives; reset it with `defaults delete <product> nook.floating-panel.top-left`.
- The log is `~/Library/Application Support/Nook/logs/<id>.log`: stdout and stderr of the process. NookKit itself writes `started (pid N)` and `panel placed at x, y` or `panel restored at x, y` (screen points, origin bottom-left), so look past those for your own lines.
- How `Package.swift` finds NookKit: an installed Nook writes `.package(url: "https://github.com/fatihsen-dev/nook", from: "<Nook version>")`, so the folder builds on any Mac against a released NookKit and can live in its own git repository. After Nook updates, the next `run` or `build` moves the nooklet onto the new NookKit first. When `NOOK_KIT_PACKAGE` is set (Nook development), it writes a local path instead.

Fix every reported diagnostic and build again before calling `run`. A nooklet that builds but logs nothing looks broken to the user: log the state changes that matter with `writeLog`.

## Nooklet layout

```text
my-widget/
├── nook.json          {"id": "com.you.my-widget", "name": "My Widget", "product": "MyWidget"}
├── Package.swift      executable target named after "product", depends on product "NookKit" of package "nook"
├── .gitignore
└── Sources/app.swift  the @main type
```

- `id`: lowercase reverse-DNS with at least two segments (`com.you.clock`); unique in the library.
- `name`: shown in Nook. `product`: a Swift type name, the executable target's name.
- `Package.swift` is generated by `nookctl new`; keep its NookKit dependency. Other SwiftPM dependencies may be added.
- Never add a `main.swift`; the entry point is the `@main` type.

## NookKit API (complete)

```swift
import NookKit
import SwiftUI

@main
struct MyWidget: Nooklet {               // Nooklet: @MainActor protocol with init() and `var body: some NookScene`
    var body: some NookScene {
        FloatingPanel(level: .floating, position: .topTrailing) {   // both arguments optional
            ContentView()
        }
    }
}
```

| Symbol | What it does |
|---|---|
| `Nooklet` | Entry point. `static main()` starts an accessory (Dock-less) app and shows the body's windows. |
| `NookScene` | What `body` returns. `FloatingPanel` is the only scene today. |
| `FloatingPanel(level:position:content:)` | Borderless, transparent, non-activating panel sized to its SwiftUI content, on all Spaces. Draggable anywhere; the last position is saved and restored. |
| `PanelLevel` | `.desktop` (on the desktop: under windows and desktop icons; NookKit raises it above the icons while the pointer is over it, so it stays draggable and clickable), `.normal`, `.floating` (above windows, default). |
| `PanelPosition` | First placement: `.center` (default), `.top`, `.bottom`, `.topLeading`, `.topTrailing`, `.bottomLeading`, `.bottomTrailing`. |
| `writeLog(_ message: String)` | Appends a `HH:mm:ss  message` line to the nooklet's log (Nook's Log tab, `nookctl logs`). Not actor-isolated; call it from any thread or task. Plain `print` also lands there. |

The panel has no background or chrome: give the content its own shape, for example `.padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))`. The panel sizes itself to the content, so give variable content a fixed or minimum frame to stop it jumping.

## macOS behaviour to plan for

- Prefer change notifications over polling (`NSWorkspace` notifications, `DistributedNotificationCenter`, Spotify's `com.spotify.client.PlaybackStateChanged`). For a display that only redraws (a clock) use `TimelineView`. For a value that should also be logged when it changes, keep it in `@State` and update it from a `.task { while !Task.isCancelled { …; try? await Task.sleep(for: .seconds(30)) } }` loop, calling `writeLog` only when the value differs from the previous one. Log state changes, never every poll.
- AppleScript or Apple Events to other apps trigger an Automation prompt and need an `NSAppleEventsUsageDescription`. A SwiftPM executable has no Info.plist, so embed one: put an `Info.plist` with `CFBundleIdentifier` and `NSAppleEventsUsageDescription` next to `Package.swift` and add `linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Info.plist"])]` to the target (see `examples/now-playing` in the Nook repository). Error -1743 means the user has not allowed it yet. Accessibility APIs need the user to allow the nooklet in System Settings.
- `MediaRemote` (system-wide now playing) is not available to third-party code on current macOS; talk to the player app directly.
- Uptime: `ProcessInfo.processInfo.systemUptime` excludes time asleep; read `kern.boottime` with `sysctl` for wall-clock uptime.
- Battery: Macs without a battery have no internal power source, so handle a missing value; pick the source whose `kIOPSTypeKey` is `kIOPSInternalBatteryType` rather than the first one (a UPS can be listed too).
- The nooklet runs from Nook's own copy of the binary, not from the package folder, so read resources through `Bundle.module` (add `resources:` to the target), never through paths relative to the source folder.

## Recipes

Complete, compiling `Sources/app.swift` files for a clock, a mini dock, a Spotify now-playing panel, a battery gauge, a memory monitor and a logging example: `references/recipes.md`. More on the website: https://nook.fatihsen.dev/#developers.
