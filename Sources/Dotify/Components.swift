import AppKit
import SwiftUI

// MARK: - Environment

private struct RevealControlsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// True while the pointer is over the player (or controls are pinned on).
    var revealControls: Bool {
        get { self[RevealControlsKey.self] }
        set { self[RevealControlsKey.self] = newValue }
    }
}

// MARK: - Window chrome

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Click-and-drag anywhere that isn't a control to move the panel.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

struct Backdrop: View {
    @EnvironmentObject private var spotify: SpotifyController
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        ZStack {
            VisualEffectBackground()
            if prefs.artBackground, let art = spotify.artwork {
                Color.clear
                    .overlay(Image(nsImage: art).resizable().scaledToFill().blur(radius: 28))
                    .clipped()
                    .opacity(0.6)
                Color.black.opacity(0.35)
            } else {
                Color.black.opacity(0.15)
            }
            WindowDragArea()
        }
    }
}

// MARK: - Pieces

struct ArtworkView: View {
    @EnvironmentObject private var spotify: SpotifyController
    var cornerRadius: CGFloat = 6

    var body: some View {
        Color.clear
            .overlay {
                if let img = spotify.artwork {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note").foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
    }
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 13
    var tint: Color?
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint ?? Color.white.opacity(hovering ? 1 : 0.85))
                .frame(width: size * 2.1, height: size * 2.1)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.14 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct PlayPauseButton: View {
    @EnvironmentObject private var spotify: SpotifyController
    var size: CGFloat = 16

    var body: some View {
        IconButton(symbol: spotify.isPlaying ? "pause.fill" : "play.fill", size: size, help: "Play/Pause (Space)") {
            spotify.playPause()
        }
    }
}

struct TransportControls: View {
    @EnvironmentObject private var spotify: SpotifyController
    var size: CGFloat = 13
    var playSize: CGFloat = 16
    var spacing: CGFloat = 2
    var vertical = false

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))
        layout {
            IconButton(symbol: "backward.fill", size: size, help: "Previous (←)") { spotify.previous() }
            PlayPauseButton(size: playSize)
            IconButton(symbol: "forward.fill", size: size, help: "Next (→)") { spotify.next() }
        }
    }
}

struct TrackLabels: View {
    @EnvironmentObject private var spotify: SpotifyController
    var titleSize: CGFloat = 13
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(spotify.track?.name ?? "")
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(.white)
            Text(spotify.track?.artist ?? "")
                .font(.system(size: titleSize - 2))
                .foregroundStyle(.white.opacity(0.65))
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .allowsHitTesting(false)
    }
}

func formatTime(_ seconds: Double) -> String {
    let s = Int(seconds.rounded(.down))
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// Progress bar that interpolates smoothly between polls. Interactive bars can be scrubbed.
struct ProgressBar: View {
    @EnvironmentObject private var spotify: SpotifyController
    var height: CGFloat = 4
    var interactive = true
    var showTimes = false

    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let duration = spotify.track?.duration ?? 0
            let live = duration > 0 ? spotify.position(at: ctx.date) / duration : 0
            let fraction = dragFraction ?? live
            VStack(spacing: 3) {
                bar(fraction: fraction, duration: duration)
                if showTimes {
                    HStack {
                        Text(formatTime(fraction * duration))
                        Spacer()
                        Text("-" + formatTime(max(duration - fraction * duration, 0)))
                    }
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private func bar(fraction: Double, duration: Double) -> some View {
        let active = interactive && (hovering || dragFraction != nil)
        let h = active ? height + 2 : height
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(spotify.accent)
                    .frame(width: max(h, geo.size.width * fraction))
            }
            .frame(height: h)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in dragFraction = min(max(v.location.x / geo.size.width, 0), 1) }
                    .onEnded { _ in
                        if let f = dragFraction { spotify.seek(to: f * duration) }
                        dragFraction = nil
                    },
                including: interactive ? .all : .none
            )
        }
        .frame(height: interactive ? 12 : height)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: active)
    }
}

struct VolumeSlider: View {
    @EnvironmentObject private var spotify: SpotifyController
    @State private var dragValue: Double?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill").font(.system(size: 9))
            GeometryReader { geo in
                let value = dragValue ?? Double(spotify.volume) / 100
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(Color.white.opacity(0.8)).frame(width: max(4, geo.size.width * value))
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let f = min(max(v.location.x / geo.size.width, 0), 1)
                            dragValue = f
                            spotify.setVolume(Int(f * 100))
                        }
                        .onEnded { _ in dragValue = nil }
                )
            }
            .frame(height: 12)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 9))
            IconButton(symbol: "hifispeaker.2", size: 10, help: "Choose Speaker (D)") {
                AppModel.shared.toggleDevices()
            }
        }
        .foregroundStyle(.white.opacity(0.55))
    }
}

/// Shown instead of a layout when there's no track to display.
struct StatusView: View {
    @EnvironmentObject private var spotify: SpotifyController
    var compact: Bool

    var body: some View {
        Group {
            if let error = spotify.errorMessage {
                content(icon: "lock.fill", text: compact ? "Needs permission" : error, button: "Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
            } else if spotify.state == .notRunning {
                content(icon: "music.note", text: compact ? "Spotify closed" : "Spotify isn't running", button: "Start") {
                    spotify.openSpotify(hidden: true)
                }
            } else {
                content(icon: "music.note", text: "Nothing playing", button: "Play") {
                    spotify.playPause()
                }
            }
        }
        .foregroundStyle(.white.opacity(0.8))
    }

    @ViewBuilder
    private func content(icon: String, text: String, button: String, action: @escaping () -> Void) -> some View {
        if compact {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    .allowsHitTesting(false)
                Spacer(minLength: 0)
                IconButton(symbol: "play.fill", size: 10, help: button, action: action)
            }
            .padding(.horizontal, 10)
        } else {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 22))
                Text(text).font(.system(size: 12)).multilineTextAlignment(.center)
                    .allowsHitTesting(false)
                Button(button, action: action).controlSize(.small)
            }
            .padding(16)
        }
    }
}
