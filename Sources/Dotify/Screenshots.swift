import AppKit
import QuartzCore

/// Renders every feature to PNGs, then quits. Run with `DOTIFY_SNAPSHOT_DIR=/some/dir`, plus `DOTIFY_DEMO=1`
/// for publishable images (`make-screenshots.sh` does both). Settings it changes are restored before quitting.
@MainActor
enum Screenshots {
    static func run(to dir: URL, model: AppModel) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let player = model.panel, let library = model.libraryPanel, let speakers = model.devicesPanel else { return }
        let prefs = model.prefs
        let state = player.state

        let saved = (layout: prefs.layout, art: prefs.artBackground, controls: prefs.alwaysShowControls,
                     frame: player.panel.frame, filters: model.library.filters)
        prefs.artBackground = true
        prefs.alwaysShowControls = false
        // Mid-screen, so the toolbar has room to open upward.
        if let screen = NSScreen.main?.visibleFrame {
            player.panel.setFrameOrigin(NSPoint(x: screen.midX - 200, y: screen.midY - 200))
        }
        try? await Task.sleep(for: .seconds(Demo.isOn ? 1 : 4))

        func shoot(_ view: NSView?, _ name: String, radius: CGFloat, alpha: CGFloat = 1) async {
            // When the screen isn't refreshing (display asleep, locked), SwiftUI holds the latest change until
            // another one arrives. A no-op change notification pushes it through; then draw and capture.
            prefs.objectWillChange.send()
            state.objectWillChange.send()
            model.library.objectWillChange.send()
            model.auth.objectWillChange.send()
            model.devices.objectWillChange.send()
            try? await Task.sleep(for: .milliseconds(600))
            guard let view else { return }
            for _ in 0..<2 {
                view.needsLayout = true
                view.layoutSubtreeIfNeeded()
                view.display()
                CATransaction.flush()
                try? await Task.sleep(for: .milliseconds(500))
            }
            write(render(view, radius: radius, alpha: alpha), to: dir.appendingPathComponent("\(name)@2x.png"))
        }

        // Layouts, at rest.
        state.hovering = false
        for layout in PlayerLayout.allCases {
            prefs.layout = layout
            await shoot(player.panel.contentView, "layout-\(layout.rawValue)", radius: layout.cornerRadius)
        }

        // Album Art with its hover controls.
        prefs.layout = .art
        state.hovering = true
        await shoot(player.panel.contentView, "layout-art-hover", radius: PlayerLayout.art.cornerRadius)

        // Quick-access toolbar.
        prefs.layout = .bar
        state.expanded = true
        await shoot(player.panel.contentView, "toolbar", radius: PlayerLayout.bar.cornerRadius)
        state.expanded = false
        state.hovering = false

        // Idle dimming, drawn at the default idle opacity.
        prefs.layout = .bar
        await shoot(player.panel.contentView, "dimmed", radius: PlayerLayout.bar.cornerRadius, alpha: prefs.idleOpacity)

        // Search & Recently Played.
        library.show(near: nil)
        model.library.query = ""
        model.library.setFilters(Set(MediaKind.allCases))
        model.library.selection = 0
        await shoot(library.panel.contentView, "search-recents", radius: 12)

        model.library.query = "lantern"
        model.library.setFilters([.song, .podcast])
        await shoot(library.panel.contentView, "search-results", radius: 12)

        if Demo.isOn {
            model.auth.enableDemo(connected: false)
            model.library.query = "lantern"
            await shoot(library.panel.contentView, "search-connect", radius: 12)
            model.auth.enableDemo(connected: true)
        }
        model.library.query = ""
        library.panel.orderOut(nil)

        // Speaker picker.
        speakers.show(near: nil)
        await shoot(speakers.panel.contentView, "speakers", radius: 12)
        speakers.hide()

        prefs.layout = saved.layout
        prefs.artBackground = saved.art
        prefs.alwaysShowControls = saved.controls
        model.library.setFilters(saved.filters)
        try? await Task.sleep(for: .milliseconds(300))
        player.panel.setFrame(saved.frame, display: false)
        NSApp.terminate(nil)
    }

    /// Draws the view at 2x with rounded corners and a soft drop shadow on a transparent background.
    private static func render(_ view: NSView, radius: CGFloat, alpha: CGFloat) -> NSBitmapImageRep? {
        view.layoutSubtreeIfNeeded()
        view.display()
        let bounds = view.bounds
        let scale: CGFloat = 2
        let pad: CGFloat = 24

        guard let content = bitmap(size: bounds.size, scale: scale) else { return nil }
        view.cacheDisplay(in: bounds, to: content)

        let outSize = NSSize(width: bounds.width + pad * 2, height: bounds.height + pad * 2)
        guard let out = bitmap(size: outSize, scale: scale), let ctx = NSGraphicsContext(bitmapImageRep: out) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let rect = NSRect(x: pad, y: pad, width: bounds.width, height: bounds.height)
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35 * alpha)
        // Shadow first, so it applies to the whole clipped layer instead of being cut off by the clip.
        shadow.set()
        ctx.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        content.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        ctx.cgContext.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
        return out
    }

    private static func bitmap(size: NSSize, scale: CGFloat) -> NSBitmapImageRep? {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        rep?.size = size
        return rep
    }

    private static func write(_ rep: NSBitmapImageRep?, to url: URL) {
        try? rep?.representation(using: .png, properties: [:])?.write(to: url)
    }
}
