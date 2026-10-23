import AppKit
import Combine
import SwiftUI

/// Borderless floating panel that can take key focus (for keyboard shortcuts)
/// without activating the app or stealing focus from whatever you're working in.
final class PlayerPanel: NSPanel {
    init(size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Titled, resizable floating panel used for the search and speaker windows.
@MainActor
func makeUtilityPanel(size: NSSize, minSize: NSSize) -> NSPanel {
    let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden
    panel.isMovableByWindowBackground = true
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.minSize = minSize
    panel.appearance = NSAppearance(named: .darkAqua)
    return panel
}

/// First open: tuck the panel just below the player. After that, the autosaved frame wins.
@MainActor
func showUtilityPanel(_ panel: NSPanel, autosaveName: String, near anchor: NSRect?) {
    if UserDefaults.standard.string(forKey: "NSWindow Frame \(autosaveName)") == nil, let anchor {
        let size = panel.frame.size
        panel.setFrameTopLeftPoint(NSPoint(x: anchor.maxX - size.width, y: anchor.minY - 8))
    }
    NSApp.activate()
    panel.makeKeyAndOrderFront(nil)
}

/// Frame math for the player window and its toolbar strip.
enum PanelGeometry {
    struct Toolbar: Equatable {
        let height: CGFloat
        let onTop: Bool
    }

    static func fitsAbove(player: NSRect, toolbarHeight: CGFloat, visibleFrame: NSRect?) -> Bool {
        guard let visibleFrame else { return true }
        return visibleFrame.maxY - player.maxY >= toolbarHeight
    }

    /// Window frame for a player frame, plus a toolbar strip on top (or bottom if there's no room above).
    static func windowFrame(player: NSRect, toolbarHeight: CGFloat?, visibleFrame: NSRect?) -> (frame: NSRect, toolbar: Toolbar?) {
        guard let h = toolbarHeight else { return (player, nil) }
        var frame = player
        frame.size.height += h
        let onTop = fitsAbove(player: player, toolbarHeight: h, visibleFrame: visibleFrame)
        if !onTop { frame.origin.y -= h }
        return (frame, Toolbar(height: h, onTop: onTop))
    }

    /// Inverse of `windowFrame`: strip the toolbar back off.
    static func playerFrame(windowFrame: NSRect, toolbar: Toolbar?) -> NSRect {
        guard let toolbar else { return windowFrame }
        var f = windowFrame
        f.size.height -= toolbar.height
        if !toolbar.onTop { f.origin.y += toolbar.height }
        return f
    }
}

/// Transient on-screen state of the player panel (not persisted).
@MainActor
final class PanelState: ObservableObject {
    @Published var hovering = false
    @Published var isKey = false
    /// Toolbar drawer (speaker, layout, search) is open.
    @Published var expanded = false
    /// Which edge the toolbar opens on: the top, unless there's no room above the player.
    @Published var toolbarOnTop = true

    /// Pointer is over the player or it has keyboard focus.
    var engaged: Bool { hovering || isKey }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class PanelController {
    let panel: PlayerPanel
    private let spotify: SpotifyController
    private let prefs: Preferences
    let state = PanelState()
    private var cancellables = Set<AnyCancellable>()
    private var keyMonitor: Any?
    private var collapseTask: Task<Void, Never>?

    private static let originKey = "panelTopLeft"

    init(spotify: SpotifyController, prefs: Preferences) {
        self.spotify = spotify
        self.prefs = prefs
        panel = PlayerPanel(size: prefs.layout.size)

        let host = FirstMouseHostingView(
            rootView: RootView()
                .environmentObject(spotify)
                .environmentObject(prefs)
                .environmentObject(AppModel.shared.auth)
                .environmentObject(state)
        )
        host.sizingOptions = []
        panel.contentView = host

        placeInitially(size: prefs.layout.size)

        Publishers.CombineLatest(prefs.$layout.removeDuplicates(), state.$expanded.removeDuplicates())
            .dropFirst()
            .sink { [weak self] layout, expanded in self?.applyFrame(layout: layout, expanded: expanded) }
            .store(in: &cancellables)
        prefs.$alwaysOnTop
            .sink { [weak self] in self?.panel.level = $0 ? .floating : .normal }
            .store(in: &cancellables)
        Publishers.CombineLatest4(prefs.$opacity, prefs.$idleOpacity, state.$hovering, state.$isKey)
            .sink { [weak self] opacity, idle, hovering, isKey in
                self?.engagementChanged(opacity: opacity, idleOpacity: idle, engaged: hovering || isKey)
            }
            .store(in: &cancellables)
        prefs.$showOnAllSpaces
            .sink { [weak self] in
                self?.panel.collectionBehavior = $0
                    ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                    : [.fullScreenAuxiliary]
            }
            .store(in: &cancellables)
        prefs.$panelVisible
            .sink { [weak self] in
                if $0 { self?.panel.orderFrontRegardless() } else { self?.panel.orderOut(nil) }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: panel)
            .sink { [weak self] _ in self?.state.isKey = true }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .sink { [weak self] _ in self?.state.isKey = false }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .sink { [weak self] _ in self?.saveOrigin() }
            .store(in: &cancellables)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    /// Fade out when idle, and close the toolbar once the pointer has left and focus has moved on.
    private func engagementChanged(opacity: Double, idleOpacity: Double, engaged: Bool) {
        let target = engaged ? opacity : min(opacity, idleOpacity)
        // Point the expand handle at the edge the toolbar will actually open on.
        if engaged && !state.expanded {
            state.toolbarOnTop = PanelGeometry.fitsAbove(player: playerFrame, toolbarHeight: prefs.layout.toolbarSize.height, visibleFrame: visibleFrame)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = engaged ? 0.12 : 0.6
            panel.animator().alphaValue = target
        }
        collapseTask?.cancel()
        guard !engaged, state.expanded else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self, !self.state.engaged else { return }
            self.state.expanded = false
        }
    }

    private func placeInitially(size: CGSize) {
        let topLeft: NSPoint
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            topLeft = NSPointFromString(saved)
        } else if let screen = NSScreen.main?.visibleFrame {
            topLeft = NSPoint(x: screen.maxX - size.width - 20, y: screen.maxY - 20)
        } else {
            topLeft = NSPoint(x: 100, y: 600)
        }
        panel.setFrame(clamped(NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)), display: true)
    }

    /// Toolbar strip currently added to the window, so it can be removed exactly on collapse.
    private var appliedToolbar: PanelGeometry.Toolbar?

    /// The player's own frame, without any toolbar strip.
    private var playerFrame: NSRect {
        PanelGeometry.playerFrame(windowFrame: panel.frame, toolbar: appliedToolbar)
    }

    private var visibleFrame: NSRect? {
        (panel.screen ?? NSScreen.main)?.visibleFrame
    }

    /// Resize for a layout change or toolbar toggle. The player itself never moves: the toolbar is
    /// added above it (or below, if it's against the top of the screen) and removed from the same edge.
    private func applyFrame(layout: PlayerLayout, expanded: Bool) {
        let current = playerFrame
        // Layout changes keep the player's top-left corner fixed.
        var player = NSRect(x: current.minX, y: current.maxY - layout.size.height,
                            width: layout.size.width, height: layout.size.height)
        if layout.size != current.size { player = clamped(player) }

        let result = PanelGeometry.windowFrame(player: player,
                                               toolbarHeight: expanded ? layout.toolbarSize.height : nil,
                                               visibleFrame: visibleFrame)
        appliedToolbar = result.toolbar
        if let toolbar = result.toolbar { state.toolbarOnTop = toolbar.onTop }
        panel.setFrame(result.frame, display: true, animate: false)
        panel.invalidateShadow()
    }

    private func clamped(_ frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        let screen = screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main
        guard let v = screen?.visibleFrame else { return frame }
        var r = frame
        r.origin.x = min(max(r.minX, v.minX), v.maxX - r.width)
        r.origin.y = min(max(r.minY, v.minY), v.maxY - r.height)
        return r
    }

    private func saveOrigin() {
        let f = playerFrame
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: f.minX, y: f.maxY)), forKey: Self.originKey)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 49: spotify.playPause(); return true            // space
        case 124: spotify.next(); return true                // →
        case 123: spotify.previous(); return true            // ←
        case 126: spotify.setVolume(spotify.volume + 10); return true  // ↑
        case 125: spotify.setVolume(spotify.volume - 10); return true  // ↓
        case 53: prefs.panelVisible = false; return true     // esc
        default: break
        }
        guard let ch = event.charactersIgnoringModifiers?.lowercased().first else { return false }
        if let layout = PlayerLayout.allCases.first(where: { $0.shortcut == ch }) {
            prefs.layout = layout
            return true
        }
        switch ch {
        case "s": spotify.toggleShuffle(); return true
        case "r": spotify.toggleRepeat(); return true
        case "t": prefs.alwaysOnTop.toggle(); return true
        case "a": prefs.artBackground.toggle(); return true
        case "f", "/": AppModel.shared.toggleLibrary(); return true
        case "e": state.expanded.toggle(); return true
        case "d": AppModel.shared.toggleDevices(); return true
        default: return false
        }
    }
}
