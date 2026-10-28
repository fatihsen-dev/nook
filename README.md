# Nook

Nook is a macOS-only manager for small native desktop apps called **nooklets**.

Build a clock, mini dock, now-playing panel, system monitor, timer, or any other always-visible tool as a normal Swift package. Nook builds and runs it as an independent process, so the nooklet keeps running even when the Nook manager window is closed.

> Nook gives developers the runtime plumbing. The interface and behaviour belong to the nooklet.

![Nook manager with Clock, Now Playing and Mini Dock nooklets](docs/nook-hero.png)

## Why Nook?

- **Free-form UI** — build the interface with SwiftUI or AppKit.
- **Native performance** — nooklets are compiled native macOS executables.
- **Independent processes** — one nooklet crashing does not take down the others.
- **Manager-independent runtime** — running nooklets survive closing Nook.
- **Simple sharing** — a nooklet is a regular folder that can live in its own Git repository.
- **No per-nooklet setup** — create, add, build, run, stop and inspect nooklets from one app.

## Requirements

- macOS 14 or later
- Xcode or the Command Line Tools (Nook builds nooklets with the Swift 6 toolchain)

Nook is currently designed for macOS only.

## Install

```bash
curl -fsSL https://github.com/fatihsen-dev/nook/releases/latest/download/install.sh | sh
```

The installer downloads the latest release, verifies its SHA-256 checksum and puts `Nook.app` in `~/Applications`. Run the same command again to update. Set `NOOK_INSTALL_DIR` to install somewhere else.

## Run Nook from source

Clone the repository from GitHub and run the manager from the repository root:

```bash
git clone https://github.com/fatihsen-dev/nook.git
cd nook
NOOK_KIT_PACKAGE=$PWD swift run Nook
```

`NOOK_KIT_PACKAGE` points newly created nooklets at your local checkout of `NookKit`, so changes to the kit are picked up immediately. The installed app does not need it: it uses the GitHub repository.

## Create your first nooklet

1. Open Nook.
2. Choose **New nooklet**.
3. Select an empty folder.
4. Enter a display name and identifier.
5. Nook creates a Swift package with a `nook.json` manifest and a starter entry file.
6. Press **Run**.

The generated structure looks like this:

```text
my-widget/
├── nook.json
├── Package.swift
├── .gitignore
└── Sources/
    └── app.swift
```

The entry file contains a type that conforms to `Nooklet`:

```swift
import NookKit
import SwiftUI

@main
struct Clock: Nooklet {
    var body: some NookScene {
        FloatingPanel(position: .topTrailing) {
            Text("Hello from Nook")
                .padding()
        }
    }
}
```

Nooklet code is intentionally unrestricted. You can use SwiftUI, AppKit, macOS notifications, AppleScript, Core Graphics, system frameworks, or your own dependencies. Nook does not provide feature-specific services such as now-playing or battery data at this stage.

## Add an existing nooklet

Use **Add existing folder** and choose a folder containing:

- `nook.json`
- `Package.swift`
- a Swift executable target that links `NookKit`

Nook validates the manifest, builds the package in release mode, installs the executable under its application support directory, and registers it with `launchd`.

## Nooklet lifecycle

Each nooklet runs as its own native process:

```text
Nook manager ── builds and registers ──▶ launchd ── runs and restarts ──▶ nooklet
```

Closing the Nook manager does not stop a running nooklet. `launchd` can start it at login and restart it after an unsuccessful exit.

Nook keeps generated runtime data under:

```text
~/Library/Application Support/Nook/
├── library.json
├── logs/<nooklet-id>.log
├── builds/<nooklet-id>.json
└── bin/<nooklet-id>/
```

Source folders are not modified when a nooklet is built, and removing a nooklet from Nook does not delete its source folder.

## NookKit

NookKit currently provides the common plumbing needed by nooklets:

- `Nooklet` — the entry point protocol
- `NookScene` — the scene abstraction
- `FloatingPanel` — borderless desktop panels with placement and dragging
- `writeLog` — append messages to the nooklet's log

Feature-specific services are intentionally out of scope for now. The `examples/` directory demonstrates how a developer can use native macOS APIs directly.

## Examples

The repository includes three example nooklets:

| Example | Description |
|---|---|
| `clock` | A small desktop clock |
| `mini-dock` | A dock built from running applications |
| `now-playing` | A Spotify controller with artwork, progress and playback controls |

Examples are separate Swift packages. To build one:

```bash
cd examples/clock
swift build
```

To run an example directly during development:

```bash
NOOK_KIT_PACKAGE=../.. swift run
```

Normally, add the example folder to Nook and use the manager so it receives the same build, install, logging and launchd lifecycle as any other nooklet.

## Development

Build the manager:

```bash
swift build
```

Run the tests:

```bash
swift test
```

The repository is split into these targets:

- `NookKit` — the SDK used by nooklets
- `NookCore` — manager business rules and ports
- `NookSystem` — macOS and toolchain adapters
- `Nook` — the SwiftUI manager application

### Releasing

Push a version tag and GitHub Actions publishes the release that `install.sh` downloads:

```bash
git tag v0.1.0
git push origin v0.1.0
```

To build the app locally without publishing:

```bash
sh scripts/package-app.sh 0.1.0 https://github.com/fatihsen-dev/nook dist
```

## Project status

Nook is an early, macOS-only project focused on the core nooklet workflow: create, add, build, run, inspect and manage small native desktop apps.

The API and manifest format may change before the first stable release.

## Contributing

Contributions are welcome. Before opening a pull request:

1. Keep changes focused.
2. Run `swift build`.
3. Run `swift test`.
4. Keep vendor-specific code inside its adapter.
5. Do not add secrets or credentials to the repository.

## License

MIT. See [LICENSE](LICENSE).
