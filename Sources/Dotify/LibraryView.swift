import AppKit
import Combine
import SwiftUI

/// Floating search / recently played window. Opens with F in the player or from the menus.
@MainActor
final class LibraryPanelController {
    let panel: NSPanel
    private let library: LibraryStore
    private var keyMonitor: Any?

    init(library: LibraryStore, auth: SpotifyAuth, spotify: SpotifyController) {
        self.library = library
        panel = makeUtilityPanel(size: NSSize(width: 380, height: 540), minSize: NSSize(width: 320, height: 320))
        panel.contentView = NSHostingView(
            rootView: LibraryView()
                .environmentObject(library)
                .environmentObject(auth)
                .environmentObject(spotify)
        )
        panel.setFrameAutosaveName("LibraryPanel")

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    func toggle(near anchor: NSRect?) {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            show(near: anchor)
        }
    }

    func show(near anchor: NSRect?) {
        showUtilityPanel(panel, autosaveName: "LibraryPanel", near: anchor)
        library.panelOpened()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125 where library.listActive: library.moveSelection(1); return true    // ↓
        case 126 where library.listActive: library.moveSelection(-1); return true   // ↑
        case 36 where library.listActive, 76 where library.listActive:              // return, enter
            if library.playSelection() { panel.orderOut(nil) }
            return true
        case 53:                                            // esc
            if library.isSearching { library.query = "" } else { panel.orderOut(nil) }
            return true
        default:
            return false
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var auth: SpotifyAuth
    @FocusState private var searchFocused: Bool
    @State private var showSetup = false

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 32)
            FilterChips()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            Divider().opacity(0.4)
            content
        }
        .background(VisualEffectBackground().ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onChange(of: library.focusRequest) { searchFocused = true }
        .onAppear { searchFocused = true }
        .onChange(of: auth.isConnected) { _, connected in
            if connected {
                showSetup = false
                Task { await library.refreshRecents() }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search songs, playlists, podcasts", text: $library.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if library.isLoading {
                ProgressView().controlSize(.small)
            } else if !library.query.isEmpty {
                Button { library.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    @ViewBuilder
    private var content: some View {
        if showSetup || (library.isSearching && !auth.isConnected) {
            ConnectView(onCancel: auth.isConnected ? nil : { showSetup = false; library.query = "" })
                .onAppear { library.listActive = false }
                .onDisappear { library.listActive = true }
        } else {
            MediaList()
            if !auth.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "link").foregroundStyle(.secondary)
                    Text("Connect Spotify to search and see full history.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Connect") { showSetup = true }.controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.2))
            }
        }
    }
}

struct FilterChips: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var spotify: SpotifyController

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MediaKind.allCases) { kind in
                let on = library.filters.contains(kind)
                Button {
                    if NSEvent.modifierFlags.contains(.option) { library.solo(kind) } else { library.toggle(kind) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: on ? "checkmark" : kind.symbol).font(.system(size: 9, weight: .bold))
                        Text(kind.title).font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(on ? spotify.accent : Color.white.opacity(0.08)))
                    .foregroundStyle(on ? Color.black.opacity(0.85) : Color.white.opacity(0.7))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Click to toggle \(kind.title). Option-click to show only \(kind.title).")
            }
            Spacer()
        }
    }
}

struct MediaList: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        let items = library.visible
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if let error = library.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .padding(8)
                    }
                    if !library.isSearching {
                        SectionHeader(title: "Recently Played")
                    }
                    ForEach(Array(items.enumerated()), id: \.element.uri) { index, item in
                        if library.isSearching && (index == 0 || items[index - 1].kind != item.kind) {
                            SectionHeader(title: item.kind.title)
                        }
                        MediaRow(item: item, selected: library.selection == index)
                            .id(item.uri)
                    }
                    if items.isEmpty && !library.isLoading {
                        Text(emptyText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: library.selection) { _, sel in
                if let sel, items.indices.contains(sel) { proxy.scrollTo(items[sel].uri, anchor: .center) }
            }
        }
    }

    private var emptyText: String {
        library.isSearching ? "No results." : "Nothing played yet. Recent songs and podcasts will show up here."
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

struct MediaRow: View {
    @EnvironmentObject private var library: LibraryStore
    let item: MediaItem
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: item.imageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: item.kind.symbol).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: item.kind == .podcast ? 8 : 4, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            .lineLimit(1)

            Spacer(minLength: 4)
            if hovering || selected {
                Image(systemName: "play.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
            } else if let date = item.playedAt, !library.isSearching {
                Text(Self.ago(date))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(selected ? 0.14 : hovering ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { library.play(item) }
        .help(item.kind == .podcast && item.isShow ? "Plays the latest episode" : "")
    }

    /// "now", "5m", "3h", "2d"
    static func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(s / 60)m"
        case ..<86400: return "\(s / 3600)h"
        default: return "\(s / 86400)d"
        }
    }
}

/// One-time setup: the user registers their own Spotify developer app and pastes its Client ID.
struct ConnectView: View {
    @EnvironmentObject private var auth: SpotifyAuth
    var onCancel: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Connect Spotify").font(.system(size: 16, weight: .semibold))
                Text("Search and listening history use Spotify's Web API, which needs a free developer app. Spotify requires the app's owner to have Premium.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                step(1, "Open the Spotify developer dashboard and create an app.") {
                    Button("Open Dashboard") { NSWorkspace.shared.open(SpotifyAuth.dashboardURL) }
                        .controlSize(.small)
                }
                step(2, "Add this Redirect URI, and tick Web API:") {
                    HStack {
                        Text(SpotifyAuth.redirectURI)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(SpotifyAuth.redirectURI, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy")
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                }
                step(3, "Paste the app's Client ID, then connect:") {
                    TextField("Client ID", text: $auth.clientID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }

                if let error = auth.authError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                HStack {
                    if let onCancel { Button("Cancel", action: onCancel) }
                    Spacer()
                    if auth.isConnecting {
                        Text("Finish signing in in your browser…").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Button(auth.isConnecting ? "Retry" : "Connect") { Task { await auth.connect() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(auth.clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(16)
        }
    }

    private func step<Content: View>(_ n: Int, _ text: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                Text(text).font(.system(size: 12))
            }
            content().padding(.leading, 14)
        }
    }
}
