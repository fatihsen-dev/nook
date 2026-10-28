# Architecture

Nook is a single Swift package (`Package.swift` at the repository root), built with SwiftPM. Minimum platform: macOS 14.

## Processes

```
Nook (manager window) ──writes──▶ ~/Library/LaunchAgents/<label>.plist
        │                                   │
        └── launchctl bootstrap/bootout ──▶ launchd ──runs & restarts──▶ nooklet process (links NookKit)
```

- **Nook** is only a manager. Closing it has no effect on running nooklets.
- **launchd** supervises every nooklet as its own LaunchAgent: started at login (`RunAtLoad`), restarted after a crash (`KeepAlive.SuccessfulExit = false`). There is no Nook daemon in between, so an idle system costs nothing beyond the nooklets themselves.
- **Nooklet** is a separate native process. A crash in one nooklet does not affect the others.

## Directories

| Path | Target | Role |
|---|---|---|
| `Sources/kit/` | `NookKit` (library product) | SDK linked by nooklets: `Nooklet`, `NookScene`, `FloatingPanel` (placement, drag to move, saved position), `writeLog`. Runs inside the nooklet process. Depends on nothing in this repository. |
| `Sources/core/` | `NookCore` | Manager business rules: manifest, scaffold, library, `NookletManager` use cases, build-error parsing, and the ports `NookletBuilder`, `BackgroundServiceController`, `NookletLibraryStore`, `BuildReportStore`, `ProcessInspector`, `CodeEditor`. Uses Foundation only. |
| `Sources/system/` | `NookSystem` | Adapters that implement the core ports: SwiftPM builds through `xcrun swift`, launchd through `launchctl`, process memory and start time through libproc, Xcode through `xcrun xed`, the library and build reports as JSON files. |
| `Sources/manager/` | `Nook` (executable) | SwiftUI manager window (dark theme from `design/nook.pen`) and the composition root: reads configuration, wires adapters into `NookletManager`. |
| `Tests/core-tests/` | `NookCoreTests` | Tests for core rules, using in-memory port implementations. |
| `Tests/system-tests/` | `NookSystemTests` | Tests for adapter output that does not need a live system service. |
| `design/` | — | Design sources: `nook.pen` (Pen canvas) and `brand/` (logo files, app icon, logo guidelines). Not part of the build. |
| `examples/` | — | Example nooklets (`clock`, `mini-dock`, `now-playing`), each its own package depending on this repository through `.package(path: "../..")`. Not part of the build. |
| `website/` | — | Static site for nook.fatihsen.dev (`index.html`, `styles.css`, `script.js`, `assets/`), plain HTML/CSS/JS with no build step, designed in `design/nook.pen`. Fonts, icons and hero images are self-hosted under `assets/`. Not part of the Swift build. |
| `install.sh` | — | One-line installer (`curl -fsSL … | sh`): downloads `Nook.zip` from the latest GitHub release, verifies it against `Nook.zip.sha256`, and installs `Nook.app` into `~/Applications`. |
| `scripts/` | — | Maintainer scripts. `package-app.sh <version> <repository-url> <output> [--sign <identity>] [--notarize]` builds a universal release binary and packages `Nook.app`, `Nook.dmg` (drag-to-Applications disk image) and `Nook.zip`, each with a SHA-256 checksum. Without `--sign` the app is signed ad hoc for local use; releases are signed with a Developer ID Application identity (hardened runtime) and notarized and stapled with an App Store Connect API key, so browser downloads open without a Gatekeeper prompt. |
| `.github/workflows/` | — | `release.yml`: on a `v*` tag, runs the tests, imports the signing certificate and notarization key from repository secrets into a temporary keychain, packages, signs and notarizes the app and publishes a GitHub release with `Nook.dmg`, `Nook.zip`, their `.sha256` files and `install.sh`. `website.yml`: on a push to `main` that touches `website/` or `install.sh`, publishes `website/` plus `install.sh` and a `CNAME` to GitHub Pages at nook.fatihsen.dev. |

Dependency direction: `Nook → NookSystem → NookCore`, `Nook → NookCore`. `NookCore` knows nothing about launchd or the Swift toolchain. `NookKit` is independent of all three.

Directories and source files use kebab-case; SwiftPM target names stay PascalCase and point at their directory with `path:`.

## Configuration

Read once at startup in `Sources/manager/configuration.swift`:

- NookKit source for scaffolded nooklets: an absolute path to a checkout of this repository, or its git URL. Taken from the `NOOK_KIT_PACKAGE` environment variable when set (local development), otherwise from the `NookKitPackage` key of the app bundle's `Info.plist`, which `scripts/package-app.sh` sets to the repository URL. Nook refuses to start when neither is present.

Data lives under `~/Library/Application Support/Nook/` (`library.json`, `logs/<nooklet id>.log`, `builds/<nooklet id>.json` with the last build report, `bin/<nooklet id>/`). Every successful build is copied into `bin/<nooklet id>/` (executable plus `*.bundle` resources) and launchd runs it from there: a nooklet folder under Desktop, Documents or Downloads would otherwise make macOS ask for folder access on every launch, and the running binary is never overwritten mid-build.

## Nooklet layout

```
<folder>/
├── nook.json
├── Package.swift        # depends on the package identity "nook", product "NookKit"
├── .gitignore
└── Sources/app.swift    # @main type conforming to Nooklet
```

Nook builds with `swift build -c release --product <product>` and finds the binary in the directory reported by `swift build --show-bin-path`; that directory differs between toolchain versions.
