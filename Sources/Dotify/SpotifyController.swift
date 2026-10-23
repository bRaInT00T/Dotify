import AppKit
import CoreImage
import SwiftUI

struct Track: Equatable {
    var id: String
    var name: String
    var artist: String
    var album: String
    var artworkURL: URL?
    /// Seconds.
    var duration: Double
}

enum PlaybackState {
    case notRunning, stopped, paused, playing
}

/// Talks to the Spotify desktop app over AppleScript. Spotify can stay hidden;
/// this app is the only UI you need to look at.
@MainActor
final class SpotifyController: ObservableObject {
    static let bundleID = "com.spotify.client"

    @Published private(set) var state: PlaybackState = .notRunning
    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    /// Heavily blurred artwork for the album-art background. Pre-rendered so it also shows in screenshots.
    @Published private(set) var blurredArtwork: NSImage?
    @Published private(set) var accent: Color = Color(red: 0.12, green: 0.84, blue: 0.38)
    @Published private(set) var volume: Int = 50
    @Published private(set) var shuffling = false
    @Published private(set) var repeating = false
    @Published private(set) var errorMessage: String?

    // Position is interpolated locally between polls so progress bars stay smooth.
    private var basePosition: Double = 0
    private var baseDate = Date()

    // Ignore polled values briefly after a local change so the UI doesn't snap back.
    private var ignorePositionUntil = Date.distantPast
    private var ignoreVolumeUntil = Date.distantPast

    private let runner = ScriptRunner()
    private var timer: Timer?
    private var refreshing = false
    private var artworkTask: Task<Void, Never>?

    /// Called once per new track or episode (used for local listening history).
    var onTrackChange: ((Track) -> Void)?

    var isPlaying: Bool { state == .playing }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    func position(at date: Date = .now) -> Double {
        guard let track else { return 0 }
        let p = isPlaying ? basePosition + date.timeIntervalSince(baseDate) : basePosition
        return min(max(p, 0), track.duration)
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    // MARK: - Polling

    private static let sep = "\u{1F}"

    private static let stateScript = """
    tell application id "com.spotify.client"
        set s to player state as string
        if s is "stopped" then return "stopped"
        set d to (ASCII character 31)
        set t to current track
        set art to ""
        try
            set art to artwork url of t
        end try
        return s & d & (id of t) & d & (name of t) & d & (artist of t) & d & (album of t) & d & art & d & ((duration of t) as string) & d & (((player position) * 1000) as integer as string) & d & ((sound volume) as string) & d & ((shuffling) as string) & d & ((repeating) as string)
    end tell
    """

    func refresh() {
        guard !refreshing else { return }
        guard isRunning else {
            state = .notRunning
            track = nil
            return
        }
        refreshing = true
        Task {
            let result = await runner.run(Self.stateScript)
            refreshing = false
            switch result {
            case .success(let raw):
                errorMessage = nil
                apply(raw)
            case .failure(let error):
                // -1743: user denied Automation permission. -600/-609: Spotify quit mid-call.
                if error.code == -1743 {
                    errorMessage = "Allow Dotify to control Spotify in System Settings → Privacy & Security → Automation."
                } else if !isRunning {
                    state = .notRunning
                    track = nil
                }
            }
        }
    }

    private func apply(_ raw: String) {
        if raw == "stopped" {
            state = .stopped
            track = nil
            return
        }
        let f = raw.components(separatedBy: Self.sep)
        guard f.count >= 11 else { return }

        state = f[0] == "playing" ? .playing : .paused
        let newTrack = Track(
            id: f[1],
            name: f[2],
            // Podcast episodes have no artist; the show name lives in album.
            artist: f[3].isEmpty ? f[4] : f[3],
            album: f[4],
            artworkURL: URL(string: f[5]),
            duration: (Double(f[6]) ?? 0) / 1000
        )
        if newTrack != track {
            let artChanged = newTrack.artworkURL != track?.artworkURL
            if newTrack.id != track?.id { onTrackChange?(newTrack) }
            track = newTrack
            if artChanged { loadArtwork(newTrack.artworkURL) }
        }
        if Date() > ignorePositionUntil {
            basePosition = (Double(f[7]) ?? 0) / 1000
            baseDate = Date()
        }
        if Date() > ignoreVolumeUntil {
            volume = Int(f[8]) ?? volume
        }
        shuffling = f[9] == "true"
        repeating = f[10] == "true"
    }

    private func loadArtwork(_ url: URL?) {
        artworkTask?.cancel()
        guard let url else {
            artwork = nil
            return
        }
        artworkTask = Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled,
                  let image = NSImage(data: data) else { return }
            setArtwork(image)
        }
    }

    private func setArtwork(_ image: NSImage) {
        artwork = image
        blurredArtwork = Self.blurred(image)
        if let c = Self.accentColor(from: image) { accent = Color(nsColor: c) }
    }

    private static func blurred(_ image: NSImage) -> NSImage? {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cg)
        guard let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(cg.width) / 18)
            .cropped(to: input.extent) as CIImage?,
              let result = CIContext().createCGImage(output, from: input.extent) else { return nil }
        return NSImage(cgImage: result, size: image.size)
    }

    /// Shows fixed made-up playback for screenshots. Doesn't touch Spotify or listening history.
    func loadDemo(track: Track, artwork image: NSImage, position: Double) {
        timer?.invalidate()
        state = .playing
        self.track = track
        basePosition = position
        baseDate = Date()
        volume = 65
        setArtwork(image)
    }

    /// Average color of the artwork, pushed bright enough to read on a dark background.
    private static func accentColor(from image: NSImage) -> NSColor? {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let avg = NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        avg.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(s * 1.3, 0.85), brightness: max(b, 0.85), alpha: 1)
    }

    // MARK: - Commands

    private func send(_ command: String) {
        guard isRunning else { return }
        Task {
            _ = await runner.run("tell application id \"com.spotify.client\" to \(command)")
            refresh()
        }
    }

    func playPause() {
        if !isRunning {
            openSpotify(hidden: true)
            return
        }
        // Optimistic toggle so the button responds instantly.
        if state == .playing {
            basePosition = position()
            state = .paused
        } else if state == .paused {
            baseDate = Date()
            state = .playing
        }
        send("playpause")
    }

    /// Plays a track, episode, album or playlist by Spotify URI, starting Spotify if needed.
    func play(uri: String) {
        guard uri.hasPrefix("spotify:"), !uri.contains("\"") else { return }
        Task {
            if !isRunning {
                openSpotify(hidden: true)
                for _ in 0..<20 where !isRunning { try? await Task.sleep(for: .milliseconds(500)) }
                try? await Task.sleep(for: .seconds(2))
            }
            send("play track \"\(uri)\"")
        }
    }

    func next() { send("next track") }
    func previous() { send("previous track") }

    func seek(to seconds: Double) {
        basePosition = seconds
        baseDate = Date()
        ignorePositionUntil = Date().addingTimeInterval(1.5)
        send("set player position to \(Int(seconds))")
    }

    func setVolume(_ value: Int) {
        let v = min(max(value, 0), 100)
        volume = v
        ignoreVolumeUntil = Date().addingTimeInterval(1.5)
        send("set sound volume to \(v)")
    }

    func toggleShuffle() {
        shuffling.toggle()
        send("set shuffling to \(shuffling)")
    }

    func toggleRepeat() {
        repeating.toggle()
        send("set repeating to \(repeating)")
    }

    // MARK: - Spotify app

    func openSpotify(hidden: Bool) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = !hidden
        config.hides = hidden
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
            Task { @MainActor in
                // Spotify sometimes shows its window late in startup regardless of `hides`.
                for delay in [1.0, 2.0] {
                    try? await Task.sleep(for: .seconds(delay))
                    if hidden { app?.hide() }
                }
                self.refresh()
            }
        }
    }

    func quitSpotify() {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).forEach { $0.terminate() }
    }

    func hideSpotify() {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).forEach { $0.hide() }
    }

    func showSpotify() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first {
            app.unhide()
            app.activate()
        } else {
            openSpotify(hidden: false)
        }
    }
}

struct ScriptError: Error {
    let code: Int
    let message: String
}

/// Runs AppleScript off the main thread on a single serial queue, caching compiled scripts.
final class ScriptRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Dotify.applescript")
    private var cache: [String: NSAppleScript] = [:]

    func run(_ source: String) async -> Result<String, ScriptError> {
        await withCheckedContinuation { cont in
            queue.async {
                let script: NSAppleScript
                if let cached = self.cache[source] {
                    script = cached
                } else if let compiled = NSAppleScript(source: source) {
                    script = compiled
                    self.cache[source] = compiled
                } else {
                    cont.resume(returning: .failure(ScriptError(code: 0, message: "Could not compile script")))
                    return
                }
                var err: NSDictionary?
                let out = script.executeAndReturnError(&err)
                if let err {
                    cont.resume(returning: .failure(ScriptError(
                        code: err[NSAppleScript.errorNumber] as? Int ?? 0,
                        message: err[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
                    )))
                } else {
                    cont.resume(returning: .success(out.stringValue ?? ""))
                }
            }
        }
    }
}
