import AppKit
import NookKit
import Observation
import SwiftUI

@main
struct NowPlaying: Nooklet {
    var body: some NookScene {
        FloatingPanel(position: .topLeading) {
            NowPlayingView(player: SpotifyPlayer())
        }
    }
}

private struct ArtworkBackdrop: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    }
                }
            }
        }
        .blur(radius: 28)
        .opacity(0.5)
        .scaleEffect(1.2)
    }
}
@MainActor
@Observable
final class ArtworkTint {
    private(set) var color = Color.white.opacity(0.28)
    private var loadedURL: URL?

    func load(from url: URL?) async {
        guard url != loadedURL else { return }
        loadedURL = url
        guard let url else {
            color = Color.white.opacity(0.28)
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                color = Color.white.opacity(0.28)
                return
            }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            let step = max(1, max(bitmap.pixelsWide, bitmap.pixelsHigh) / 12)
            var red = 0.0
            var green = 0.0
            var blue = 0.0
            var count = 0.0
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
                    guard let sample = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    red += sample.redComponent
                    green += sample.greenComponent
                    blue += sample.blueComponent
                    count += 1
                }
            }
            guard count > 0 else { return }
            color = Color(nsColor: NSColor(
                calibratedRed: red / count,
                green: green / count,
                blue: blue / count,
                alpha: 0.65))
        } catch {
            writeLog("artwork tint unavailable: \(error.localizedDescription)")
            color = Color.white.opacity(0.28)
        }
    }
}

private struct ArtworkBorder: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(color, lineWidth: 1)
            .shadow(color: color.opacity(0.24), radius: 4)
    }
}

private struct TrackArtwork: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.system(size: 22, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.08))
    }
}

struct NowPlayingView: View {
    let player: SpotifyPlayer
    @State private var artworkTint = ArtworkTint()

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
            TrackArtwork(url: player.track?.artworkURL)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(player.track?.title ?? player.message)
                    .font(.system(size: 14, weight: .semibold))
                Text(player.track?.artist ?? "Spotify")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(width: 180, alignment: .leading)
            HStack(spacing: 4) {
                control("backward.fill") { player.send("previous track") }
                control(player.track?.isPlaying == true ? "pause.fill" : "play.fill") { player.send("playpause") }
                control("forward.fill") { player.send("next track") }
            }
        }
        if let track = player.track, track.duration > 0 {
            ProgressView(value: min(max(track.position, 0), track.duration), total: track.duration)
                .tint(artworkTint.color)
                .frame(maxWidth: .infinity)
                .scaleEffect(x: 1, y: 0.55, anchor: .center)
            }
        }
        .padding(12)
        .background {
            ZStack {
                ArtworkBackdrop(url: player.track?.artworkURL)
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [.black.opacity(0.18), .black.opacity(0.58)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
            }
        }
        .overlay { ArtworkBorder(color: artworkTint.color) }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task(id: player.track?.artworkURL) { await artworkTint.load(from: player.track?.artworkURL) }
        .task { await player.poll() }
    }

    private func control(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
