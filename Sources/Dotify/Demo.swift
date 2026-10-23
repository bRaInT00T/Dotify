import AppKit
import CoreAudio

/// Made-up content for screenshots, so published images never show real artwork, accounts or device names.
/// Enabled with `DOTIFY_DEMO=1` (see `make-screenshots.sh`).
enum Demo {
    static let isOn = ProcessInfo.processInfo.environment["DOTIFY_DEMO"] == "1"

    @MainActor
    static func load(into model: AppModel) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dotify-demo-art", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func art(_ name: String, _ hues: (CGFloat, CGFloat), shape: ArtShape) -> URL {
            let url = dir.appendingPathComponent("\(name).png")
            if let png = artwork(hues: hues, shape: shape).pngData { try? png.write(to: url) }
            return url
        }

        let nowPlaying = art("golden-hour", (0.03, 0.88), shape: .sun)
        let focus = art("late-night", (0.62, 0.78), shape: .moon)
        let slowRoads = art("slow-roads", (0.45, 0.58), shape: .waves)
        let paperMoons = art("paper-moons", (0.75, 0.92), shape: .rings)
        let staticBloom = art("static-bloom", (0.12, 0.30), shape: .bars)
        let coffee = art("sunday", (0.08, 0.15), shape: .rings)
        let tinyTools = art("tiny-tools", (0.50, 0.66), shape: .bars)
        let lanternHour = art("lantern-hour", (0.98, 0.10), shape: .moon)

        let image = NSImage(contentsOf: nowPlaying) ?? NSImage()
        model.spotify.loadDemo(
            track: Track(id: "spotify:track:demo", name: "Golden Hour Drive", artist: "The Paper Lanterns",
                         album: "Neon Coast", artworkURL: nowPlaying, duration: 214),
            artwork: image,
            position: 83
        )

        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        model.library.loadDemo(
            recents: [
                MediaItem(uri: "demo:1", kind: .song, title: "Golden Hour Drive", subtitle: "The Paper Lanterns", imageURL: nowPlaying, playedAt: ago(0)),
                MediaItem(uri: "demo:2", kind: .podcast, title: "Ep. 112: Why We Love Night Drives", subtitle: "Episode · Slow Roads", imageURL: slowRoads, playedAt: ago(140)),
                MediaItem(uri: "demo:3", kind: .playlist, title: "Late Night Focus", subtitle: "Playlist · Alex", imageURL: focus, playedAt: ago(320)),
                MediaItem(uri: "demo:4", kind: .song, title: "Paper Moons", subtitle: "Wren & the Tides", imageURL: paperMoons, playedAt: ago(1500)),
                MediaItem(uri: "demo:5", kind: .song, title: "Static Bloom", subtitle: "Kilo Harbor", imageURL: staticBloom, playedAt: ago(1700)),
                MediaItem(uri: "demo:6", kind: .playlist, title: "Sunday Morning Coffee", subtitle: "Playlist · Sam", imageURL: coffee, playedAt: ago(2900)),
                MediaItem(uri: "demo:7", kind: .podcast, title: "Ep. 48: Building Tiny Tools", subtitle: "Episode · Small Software", imageURL: tinyTools, playedAt: ago(4400)),
            ],
            results: [
                MediaItem(uri: "demo:s1", kind: .song, title: "Lanterns", subtitle: "Wren & the Tides", imageURL: paperMoons),
                MediaItem(uri: "demo:s2", kind: .song, title: "Golden Hour Drive", subtitle: "The Paper Lanterns", imageURL: nowPlaying),
                MediaItem(uri: "demo:s3", kind: .song, title: "Lantern Light", subtitle: "Kilo Harbor", imageURL: staticBloom),
                MediaItem(uri: "demo:s4", kind: .playlist, title: "Lantern Festival Mix", subtitle: "Playlist · Alex", imageURL: focus),
                MediaItem(uri: "spotify:show:demo", kind: .podcast, title: "The Lantern Hour", subtitle: "Podcast", imageURL: lanternHour),
                MediaItem(uri: "demo:s6", kind: .podcast, title: "Ep. 7: Paper Lanterns", subtitle: "Episode · 2026-09-14", imageURL: lanternHour),
            ]
        )

        model.devices.loadDemo(
            outputs: [
                AudioOutput(id: 1, name: "MacBook Pro Speakers", transport: kAudioDeviceTransportTypeBuiltIn),
                AudioOutput(id: 2, name: "Studio Display", transport: kAudioDeviceTransportTypeDisplayPort),
                AudioOutput(id: 3, name: "Desk Speakers", transport: kAudioDeviceTransportTypeUSB),
            ],
            defaultOutput: 1,
            bluetooth: [BluetoothSpeaker(id: "00-00-00-00-00-01", name: "Travel Headphones", isConnected: false)],
            airplay: [AirPlaySpeaker(name: "Living Room", isSonos: true), AirPlaySpeaker(name: "Bedroom TV", isSonos: false)],
            connect: [
                ConnectDevice(id: "demo-kitchen", name: "Kitchen", type: "Speaker", isActive: false, isRestricted: false, volumePercent: 40, supportsVolume: true),
                ConnectDevice(id: "demo-den", name: "Den TV", type: "TV", isActive: false, isRestricted: false, volumePercent: 30, supportsVolume: true),
                ConnectDevice(id: "demo-phone", name: "Alex's Phone", type: "Smartphone", isActive: false, isRestricted: false, volumePercent: 70, supportsVolume: true),
            ]
        )

        model.auth.enableDemo(connected: true)
    }

    // MARK: - Generated artwork

    enum ArtShape { case sun, moon, waves, rings, bars }

    /// Simple abstract cover: a two-hue gradient with a shape.
    static func artwork(hues: (CGFloat, CGFloat), shape: ArtShape, size: CGFloat = 600) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let top = NSColor(hue: hues.0, saturation: 0.75, brightness: 0.95, alpha: 1)
            let bottom = NSColor(hue: hues.1, saturation: 0.85, brightness: 0.45, alpha: 1)
            NSGradient(starting: bottom, ending: top)?.draw(in: rect, angle: 90)
            let light = NSColor.white.withAlphaComponent(0.85)
            let soft = NSColor.white.withAlphaComponent(0.25)
            let s = rect.width
            switch shape {
            case .sun:
                light.setFill()
                NSBezierPath(ovalIn: NSRect(x: s * 0.3, y: s * 0.38, width: s * 0.4, height: s * 0.4)).fill()
                NSColor(hue: hues.1, saturation: 0.9, brightness: 0.3, alpha: 1).setFill()
                for i in 0..<4 {
                    NSBezierPath(rect: NSRect(x: 0, y: s * (0.08 + CGFloat(i) * 0.07), width: s, height: s * 0.035)).fill()
                }
                NSBezierPath(rect: NSRect(x: 0, y: 0, width: s, height: s * 0.08)).fill()
            case .moon:
                light.setFill()
                NSBezierPath(ovalIn: NSRect(x: s * 0.28, y: s * 0.28, width: s * 0.44, height: s * 0.44)).fill()
                NSColor(hue: hues.1, saturation: 0.85, brightness: 0.45, alpha: 1).setFill()
                NSBezierPath(ovalIn: NSRect(x: s * 0.4, y: s * 0.36, width: s * 0.4, height: s * 0.4)).fill()
            case .waves:
                light.setStroke()
                for i in 0..<6 {
                    let path = NSBezierPath()
                    let y = s * (0.2 + CGFloat(i) * 0.12)
                    path.move(to: NSPoint(x: 0, y: y))
                    path.curve(to: NSPoint(x: s, y: y), controlPoint1: NSPoint(x: s * 0.33, y: y + s * 0.08), controlPoint2: NSPoint(x: s * 0.66, y: y - s * 0.08))
                    path.lineWidth = s * 0.02
                    path.stroke()
                }
            case .rings:
                for i in 0..<5 {
                    (i % 2 == 0 ? light : soft).setStroke()
                    let inset = s * (0.12 + CGFloat(i) * 0.07)
                    let path = NSBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset))
                    path.lineWidth = s * 0.025
                    path.stroke()
                }
            case .bars:
                for i in 0..<9 {
                    (i % 3 == 0 ? light : soft).setFill()
                    let h = s * (0.2 + 0.5 * abs(sin(CGFloat(i) * 0.9)))
                    NSBezierPath(roundedRect: NSRect(x: s * (0.1 + CGFloat(i) * 0.09), y: s * 0.2, width: s * 0.05, height: h),
                                 xRadius: s * 0.025, yRadius: s * 0.025).fill()
                }
            }
            return true
        }
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
