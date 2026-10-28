# Nook

Nook is a macOS-only manager for nooklets, small native apps such as desktop widgets, mini docks, now-playing panels and similar always-visible tools. A developer writes a nooklet as a Swift package with a fixed layout, and Nook builds it, runs it in the background, and keeps it running independently of the Nook window.

## Goals

- Free-form design: a nooklet draws its own interface with SwiftUI or AppKit; Nook imposes no visual components.
- Low resource use: every nooklet is a small native process with no web view and no interpreter.
- Independence: nooklets keep running when Nook is closed, start at login, and restart after a crash.
- Zero per-app setup: creating, adding, building and running a nooklet happens from the Nook interface.
- Shareable: a nooklet is a plain folder that can live in its own git repository.

## Domain terms

- **Nooklet** — a folder containing a `nook.json` manifest and a Swift package whose executable links NookKit.
- **Manifest** (`nook.json`) — the identity of a nooklet: `id` (lowercase reverse-DNS, unique), `name` (display name), `product` (the executable product of the package).
- **NookKit** — the Swift library a nooklet links. It provides the `Nooklet` entry point and the scenes, such as `FloatingPanel`, that turn SwiftUI views into borderless desktop windows.
- **Library** — the list of nooklet folders Nook manages.
- **Entry file** — `Sources/app.swift` in a scaffolded nooklet, the type marked `@main` that conforms to `Nooklet`.
- **Scaffold** — the starter files Nook writes into an empty folder when a new nooklet is created.

## Scope

- Create a nooklet from the starter template in a chosen folder.
- Add an existing nooklet folder.
- Build a nooklet in release mode and run it as a background service.
- Stop, restart and remove nooklets; show build errors.

## Out of scope

- Platforms other than macOS.
- Web-based (HTML/JS) nooklets. The manifest is designed so another kind can be added later without changing native nooklets.
- Sandboxing nooklets: a nooklet is native code built from source, trusted like any package the user builds.
- Prebuilt or notarized nooklet binaries.
- Feature services in NookKit for now (now playing, running apps, battery, weather…); they may be added later. Today NookKit only provides the plumbing every nooklet needs: the entry point, panels, placement and dragging, logging. What a nooklet shows and where it gets its data is written by its developer with plain macOS APIs; `examples/` shows how.
