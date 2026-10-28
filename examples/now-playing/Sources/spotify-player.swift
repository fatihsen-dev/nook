import AppKit
import NookKit
import Observation

let pollInterval: Duration = .seconds(1)
let playbackChangedNotification = Notification.Name("com.spotify.client.PlaybackStateChanged")
let spotifyBundleIdentifier = "com.spotify.client"
let fieldSeparator = "\u{1F}"
let notRunningMessage = "Spotify is not running"
let notPlayingMessage = "Nothing playing"
let permissionMessage = "Allow Automation in System Settings"
let permissionErrorNumbers: Set<Int> = [-1743, -1744]

struct Track: Equatable {
    let title: String
    let artist: String
    let artworkURL: URL?
    let position: Double
    let duration: Double
    let isPlaying: Bool
}

enum ScriptResult {
    case value(String)
    case denied
    case failed(String)
}

@MainActor
@Observable
final class SpotifyPlayer {
    private(set) var track: Track? {
        didSet { logChange(from: oldValue, to: track) }
    }
    private(set) var message = notRunningMessage
    private var lastFailure: String?

    func poll() async {
        let observer = DistributedNotificationCenter.default().addObserver(forName: playbackChangedNotification, object: nil, queue: .main) { [weak self] notification in
            let info = notification.userInfo ?? [:]
            let title = info["Name"] as? String
            let artist = info["Artist"] as? String
            let state = info["Player State"] as? String
            MainActor.assumeIsolated { self?.apply(title: title, artist: artist, state: state) }
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }
        while !Task.isCancelled {
            refresh()
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return
            }
        }
    }

    func send(_ command: String) {
        guard isSpotifyRunning else { return }
        writeLog("command: \(command)")
        handle(run("tell application id \"\(spotifyBundleIdentifier)\" to \(command)"))
        refresh()
    }

    private func apply(title: String?, artist: String?, state: String?) {
        guard state != "Stopped", let title, let artist else {
            show(nil, message: notPlayingMessage)
            return
        }
        let artworkURL = self.track?.artworkURL
        let position = self.track?.position ?? 0
        let duration = self.track?.duration ?? 0
        show(Track(title: title, artist: artist, artworkURL: artworkURL, position: position, duration: duration, isPlaying: state == "Playing"), message: notPlayingMessage)
    }

    private var isSpotifyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: spotifyBundleIdentifier).isEmpty
    }

    private func refresh() {
        guard isSpotifyRunning else {
            show(nil, message: notRunningMessage)
            return
        }
        let script = """
        tell application id "\(spotifyBundleIdentifier)"
            if player state is stopped then return ""
            return (name of current track) & "\(fieldSeparator)" & (artist of current track) & "\(fieldSeparator)" & (artwork url of current track) & "\(fieldSeparator)" & (player position as text) & "\(fieldSeparator)" & (duration of current track as text) & "\(fieldSeparator)" & (player state as text)
        end tell
        """
        guard case .value(let output) = handle(run(script)), !output.isEmpty else {
            if message != permissionMessage { show(nil, message: notPlayingMessage) }
            return
        }
        let fields = output.components(separatedBy: fieldSeparator)
        guard fields.count == 6,
              let position = Double(fields[3].replacingOccurrences(of: ",", with: ".")),
              let durationMilliseconds = Double(fields[4].replacingOccurrences(of: ",", with: ".")) else {
            writeLog("unexpected Spotify reply: \(output)")
            return
        }
        let artworkURL = URL(string: fields[2])
        show(Track(title: fields[0], artist: fields[1], artworkURL: artworkURL, position: position, duration: durationMilliseconds / 1000, isPlaying: fields[5] == "playing"), message: notPlayingMessage)
    }

    private func show(_ newTrack: Track?, message newMessage: String) {
        if newTrack == nil && (track != nil || message != newMessage) {
            writeLog(newMessage)
        }
        if track != newTrack { track = newTrack }
        if message != newMessage { message = newMessage }
    }

    @discardableResult
    private func handle(_ result: ScriptResult) -> ScriptResult {
        switch result {
        case .denied:
            show(nil, message: permissionMessage)
        case .failed(let reason):
            if reason != lastFailure { writeLog("Spotify did not answer: \(reason)") }
            lastFailure = reason
        case .value:
            lastFailure = nil
        }
        return result
    }

    private func run(_ source: String) -> ScriptResult {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else {
            return .value(result?.stringValue ?? "")
        }
        let number = error[NSAppleScript.errorNumber] as? Int ?? 0
        if permissionErrorNumbers.contains(number) {
            return .denied
        }
        return .failed("\(error[NSAppleScript.errorMessage] as? String ?? "unknown error") (\(number))")
    }

    private func logChange(from oldTrack: Track?, to newTrack: Track?) {
        guard let newTrack else { return }
        if oldTrack?.title != newTrack.title || oldTrack?.artist != newTrack.artist {
            writeLog("now playing: \(newTrack.title) — \(newTrack.artist)\(newTrack.isPlaying ? "" : " (paused)")")
        } else if oldTrack?.isPlaying != newTrack.isPlaying {
            writeLog(newTrack.isPlaying ? "resumed" : "paused")
        }
    }
}
