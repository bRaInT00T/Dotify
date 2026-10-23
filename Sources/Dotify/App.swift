import AppKit
import SwiftUI

@MainActor
final class AppModel {
    static let shared = AppModel()
    let spotify = SpotifyController()
    let prefs = Preferences()
    let auth = SpotifyAuth()
    lazy var api = SpotifyAPI(auth: auth)
    lazy var library = LibraryStore(api: api, auth: auth, spotify: spotify)
    lazy var devices = DeviceStore(api: api, auth: auth)
    var panel: PanelController?
    var libraryPanel: LibraryPanelController?
    var devicesPanel: DevicePanelController?

    func toggleLibrary() {
        libraryPanel?.toggle(near: prefs.panelVisible ? panel?.panel.frame : nil)
    }

    func toggleDevices() {
        devicesPanel?.toggle(near: prefs.panelVisible ? panel?.panel.frame : nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon; the menu bar item and the floating panel are the whole UI.
        NSApp.setActivationPolicy(.accessory)
        let model = AppModel.shared
        let library = model.library
        model.spotify.onTrackChange = { library.record($0) }
        model.spotify.start()
        model.panel = PanelController(spotify: model.spotify, prefs: model.prefs)
        model.libraryPanel = LibraryPanelController(library: library, auth: model.auth, spotify: model.spotify)
        model.devicesPanel = DevicePanelController(devices: model.devices, auth: model.auth, spotify: model.spotify)

        // Dev aid: DOTIFY_SNAPSHOT_DIR=/some/dir renders every layout to PNG, then quits.
        if let dir = snapshotDir {
            Task { await snapshotLayouts(to: URL(fileURLWithPath: dir), model: model) }
        } else if model.prefs.launchSpotifyOnStart && !model.spotify.isRunning {
            model.spotify.openSpotify(hidden: true)
        }
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        let model = AppModel.shared
        if model.prefs.quitSpotifyOnExit && snapshotDir == nil {
            model.spotify.quitSpotify()
        }
    }

    private var snapshotDir: String? {
        ProcessInfo.processInfo.environment["DOTIFY_SNAPSHOT_DIR"]
    }

    @MainActor
    private func snapshotLayouts(to dir: URL, model: AppModel) async {
        try? await Task.sleep(for: .seconds(4))
        let original = model.prefs.layout
        for layout in PlayerLayout.allCases {
            model.prefs.layout = layout
            try? await Task.sleep(for: .milliseconds(1500))
            guard let view = model.panel?.panel.contentView else { continue }
            view.layoutSubtreeIfNeeded()
            view.display()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: dir.appendingPathComponent("\(layout.rawValue).png"))
        }
        // Expanded + hovered variants, to check the toolbar fits every layout.
        if let state = model.panel?.state {
            state.hovering = true
            state.expanded = true
            for layout in PlayerLayout.allCases {
                model.prefs.layout = layout
                try? await Task.sleep(for: .milliseconds(1200))
                guard let view = model.panel?.panel.contentView else { continue }
                view.layoutSubtreeIfNeeded()
                view.display()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: dir.appendingPathComponent("\(layout.rawValue)-expanded.png"))
            }
            state.expanded = false
            state.hovering = false
        }
        model.prefs.layout = original

        if let lib = model.libraryPanel {
            lib.show(near: model.panel?.panel.frame)
            try? await Task.sleep(for: .milliseconds(1500))
            if let view = lib.panel.contentView {
                view.layoutSubtreeIfNeeded()
                view.display()
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("library.png"))
                }
            }
            // Typing while disconnected shows the Connect form.
            if !model.auth.isConnected {
                model.library.query = "test"
                try? await Task.sleep(for: .milliseconds(800))
                if let view = lib.panel.contentView {
                    view.layoutSubtreeIfNeeded()
                    view.display()
                    if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("library-connect.png"))
                    }
                }
                model.library.query = ""
            }
            lib.panel.orderOut(nil)
        }

        if let dev = model.devicesPanel {
            dev.show(near: model.panel?.panel.frame)
            dev.panel.setContentSize(NSSize(width: 320, height: 760))
            try? await Task.sleep(for: .milliseconds(3500))
            if let view = dev.panel.contentView {
                view.layoutSubtreeIfNeeded()
                view.display()
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("devices.png"))
                }
            }
            let lines = model.devices.connectDevices.map { "\($0.name) | \($0.type) | active=\($0.isActive) restricted=\($0.isRestricted)" }
                + model.devices.airplay.map { "AirPlay: \($0.name) sonos=\($0.isSonos)" }
            try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("devices.txt"), atomically: true, encoding: .utf8)
        }
        NSApp.terminate(nil)
    }
}

@main
struct DotifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PlayerMenuItems()
                .environmentObject(AppModel.shared.spotify)
                .environmentObject(AppModel.shared.prefs)
                .environmentObject(AppModel.shared.auth)
        } label: {
            Image(systemName: "music.note")
        }
    }
}

/// Shared by the menu bar item and the panel's right-click menu.
struct PlayerMenuItems: View {
    @EnvironmentObject private var spotify: SpotifyController
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var auth: SpotifyAuth

    var body: some View {
        if let t = spotify.track {
            Text("\(t.name) — \(t.artist)")
        }
        Button(spotify.isPlaying ? "Pause" : "Play") { spotify.playPause() }
        Button("Next Track") { spotify.next() }
        Button("Previous Track") { spotify.previous() }

        Divider()

        Button("Search & Recently Played…") { AppModel.shared.toggleLibrary() }
            .keyboardShortcut("f")
        Button("Choose Speaker…") { AppModel.shared.toggleDevices() }
            .keyboardShortcut("d")
        if auth.isConnected {
            Button("Disconnect Spotify Account") { auth.disconnect() }
        }

        Divider()

        Picker("Layout", selection: $prefs.layout) {
            ForEach(PlayerLayout.allCases) { layout in
                Text("\(layout.title)  (\(String(layout.shortcut)))").tag(layout)
            }
        }
        Picker("Opacity", selection: $prefs.opacity) {
            Text("100%").tag(1.0)
            Text("85%").tag(0.85)
            Text("70%").tag(0.7)
            Text("50%").tag(0.5)
        }
        Picker("Dim When Idle", selection: $prefs.idleOpacity) {
            Text("Off").tag(1.0)
            Text("To 70%").tag(0.7)
            Text("To 50%").tag(0.5)
            Text("To 30%").tag(0.3)
            Text("To 15%").tag(0.15)
        }
        Toggle("Show Mini Player", isOn: $prefs.panelVisible)
        Toggle("Always on Top", isOn: $prefs.alwaysOnTop)
        Toggle("Show on All Spaces", isOn: $prefs.showOnAllSpaces)
        Toggle("Album Art Background", isOn: $prefs.artBackground)
        Toggle("Always Show Controls", isOn: $prefs.alwaysShowControls)

        Divider()

        Toggle("Start Spotify Hidden on Launch", isOn: $prefs.launchSpotifyOnStart)
        Toggle("Quit Spotify When Dotify Quits", isOn: $prefs.quitSpotifyOnExit)

        if spotify.state == .notRunning {
            Button("Start Spotify in Background") { spotify.openSpotify(hidden: true) }
        } else {
            Button("Show Spotify") { spotify.showSpotify() }
            Button("Hide Spotify") { spotify.hideSpotify() }
        }

        Divider()

        Button("Quit Dotify") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
