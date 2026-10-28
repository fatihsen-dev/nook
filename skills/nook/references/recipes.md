# Nooklet recipes

Each recipe is a complete `Sources/app.swift` and compiles against NookKit as is. Replace the `Sources/app.swift` of a nooklet created with `nookctl new`, then `nookctl run .`. The `@main` struct can have any name; the executable target is named after `product` in `nook.json`.

## Clock

A clock pinned to the top-right corner. `TimelineView` redraws once a minute; no timer needed.

```swift
import NookKit
import SwiftUI

@main
struct Clock: Nooklet {
    var body: some NookScene {
        FloatingPanel(position: .topTrailing) {
            TimelineView(.everyMinute) { context in
                Text(context.date, style: .time)
                    .font(.system(size: 56, weight: .semibold))
            }
        }
    }
}
```

## Mini dock

Running apps from `NSWorkspace`, with their real icons; tap to activate.

```swift
import AppKit
import NookKit
import SwiftUI

@main
struct MiniDock: Nooklet {
    var body: some NookScene {
        FloatingPanel(level: .floating, position: .bottom) {
            DockView()
        }
    }
}

struct DockView: View {
    @State private var apps = NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(apps, id: \.processIdentifier) { app in
                Image(nsImage: app.icon ?? NSImage())
                    .resizable()
                    .frame(width: 40, height: 40)
                    .onTapGesture { app.activate() }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
```

## Now playing (Spotify)

Listens to Spotify's distributed notification instead of polling. Spotify posts it on every track or state change.

```swift
import AppKit
import NookKit
import SwiftUI

let spotifyChanged = Notification.Name("com.spotify.client.PlaybackStateChanged")

@main
struct NowPlaying: Nooklet {
    var body: some NookScene {
        FloatingPanel(position: .topLeading) {
            TrackView()
        }
    }
}

struct TrackView: View {
    @State private var title = "Nothing playing"
    @State private var artist = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            Text(artist).foregroundStyle(.secondary)
        }
        .padding(16)
        .onReceive(DistributedNotificationCenter.default()
            .publisher(for: spotifyChanged)) { note in
            title = note.userInfo?["Name"] as? String ?? title
            artist = note.userInfo?["Artist"] as? String ?? artist
        }
    }
}
```

## Battery

Battery level of the internal battery from IOKit power sources, on the desktop level so it sits under windows. Shows 0 on a Mac without a battery.

```swift
import IOKit.ps
import NookKit
import SwiftUI

@main
struct Battery: Nooklet {
    var body: some NookScene {
        FloatingPanel(level: .desktop, position: .bottomTrailing) {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Gauge(value: Double(batteryLevel() ?? 0), in: 0...100) {
                    Image(systemName: "battery.75percent")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .padding(12)
            }
        }
    }
}

func batteryLevel() -> Int? {
    let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
    let battery = sources
        .compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
        .first { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }
    return battery?[kIOPSCurrentCapacityKey] as? Int
}
```

## System stats

Used memory via `host_statistics64`, refreshed every two seconds.

```swift
import Darwin
import NookKit
import SwiftUI

@main
struct SystemStats: Nooklet {
    var body: some NookScene {
        FloatingPanel(position: .topTrailing) {
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                Text("RAM \(usedMemory(), format: .byteCount(style: .memory))")
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
            }
        }
    }
}

func usedMemory() -> Int64 {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
        MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }
    let pages = Int64(stats.active_count) + Int64(stats.wire_count)
        + Int64(stats.compressor_page_count)
    return pages * Int64(vm_kernel_page_size)
}
```

## Logging

`writeLog` calls show up live in Nook's Log tab and in `nookctl logs`.

```swift
import NookKit
import SwiftUI

@main
struct Pomodoro: Nooklet {
    var body: some NookScene {
        FloatingPanel(position: .center) {
            TimerView()
        }
    }
}

struct TimerView: View {
    @State private var isRunning = false

    var body: some View {
        Button(isRunning ? "Stop" : "Focus 25 min") {
            isRunning.toggle()
            writeLog(isRunning ? "focus started" : "focus stopped")
        }
        .padding(16)
        .onAppear { writeLog("ready") }
    }
}
```
