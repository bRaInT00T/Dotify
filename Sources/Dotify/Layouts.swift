import SwiftUI

struct RootView: View {
    @EnvironmentObject private var spotify: SpotifyController
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var state: PanelState

    var body: some View {
        let layout = prefs.layout
        let size = layout.panelSize(expanded: state.expanded)
        let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
        ZStack(alignment: .top) {
            Backdrop()
            VStack(spacing: 0) {
                if state.expanded && state.toolbarOnTop { toolbar(layout) }
                player(layout)
                    .frame(width: layout.size.width, height: layout.size.height)
                    .overlay(alignment: state.toolbarOnTop ? .top : .bottom) {
                        if state.hovering && !state.expanded {
                            ExpandHandle(onTop: state.toolbarOnTop).transition(.opacity)
                        }
                    }
                if state.expanded && !state.toolbarOnTop { toolbar(layout) }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        .environment(\.revealControls, state.hovering || prefs.alwaysShowControls)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { state.hovering = h } }
        .contextMenu { PlayerMenuItems() }
        .environment(\.colorScheme, .dark)
    }

    private func toolbar(_ layout: PlayerLayout) -> some View {
        PlayerToolbar(vertical: layout.toolbarIsVertical, onTop: state.toolbarOnTop)
            .frame(width: layout.toolbarSize.width, height: layout.toolbarSize.height)
    }

    @ViewBuilder
    private func player(_ layout: PlayerLayout) -> some View {
        if spotify.track == nil {
            if layout == .column {
                ColumnStatus()
            } else {
                StatusView(compact: layout.isCompact)
            }
        } else {
            switch layout {
            case .ticker: TickerLayout()
            case .pill: PillLayout()
            case .bar: BarLayout()
            case .card: CardLayout()
            case .art: ArtLayout()
            case .column: ColumnLayout()
            }
        }
    }
}

/// Small tab on the top edge (bottom if the player is against the top of the screen), shown on hover,
/// that opens the toolbar.
struct ExpandHandle: View {
    @EnvironmentObject private var state: PanelState
    let onTop: Bool
    @State private var hovering = false

    var body: some View {
        Button { state.expanded = true } label: {
            Image(systemName: onTop ? "chevron.compact.up" : "chevron.compact.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.75))
                .frame(width: 34, height: 11)
                .background(Capsule().fill(Color.white.opacity(hovering ? 0.3 : 0.16)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Show speaker, layout and search buttons (E)")
        .padding(onTop ? .top : .bottom, 1)
    }
}

/// Quick access to the speaker picker, layouts and search.
struct PlayerToolbar: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var state: PanelState
    let vertical: Bool
    let onTop: Bool

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))
        ZStack {
            Color.black.opacity(0.18)
            layout {
                IconButton(symbol: "hifispeaker.2", size: 11, help: "Choose Speaker (D)") { AppModel.shared.toggleDevices() }
                layoutMenu
                IconButton(symbol: "magnifyingglass", size: 11, help: "Search & Recently Played (F)") { AppModel.shared.toggleLibrary() }
                IconButton(symbol: onTop ? "chevron.compact.down" : "chevron.compact.up", size: 11, help: "Hide buttons (E)") {
                    state.expanded = false
                }
            }
        }
        .overlay(alignment: onTop ? .bottom : .top) {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5)
        }
    }

    private var layoutMenu: some View {
        Menu {
            Picker("Layout", selection: $prefs.layout) {
                ForEach(PlayerLayout.allCases) { l in
                    Label("\(l.title)  (\(String(l.shortcut)))", systemImage: l.symbol).tag(l)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 23, height: 23)
        .help("Change Layout (1–6)")
    }
}

/// One line of text. The least distracting option.
struct TickerLayout: View {
    @EnvironmentObject private var spotify: SpotifyController
    @Environment(\.revealControls) private var reveal

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: spotify.isPlaying ? "waveform" : "pause")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(spotify.accent)
                .frame(width: 12)
                .allowsHitTesting(false)
            (Text(spotify.track?.name ?? "").foregroundColor(.white)
             + Text("  ·  " + (spotify.track?.artist ?? "")).foregroundColor(.white.opacity(0.55)))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .allowsHitTesting(false)
            Spacer(minLength: 0)
            if reveal {
                TransportControls(size: 8, playSize: 9, spacing: 0)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
    }
}

struct PillLayout: View {
    @Environment(\.revealControls) private var reveal

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(cornerRadius: 14).frame(width: 28, height: 28)
            TrackLabels(titleSize: 12)
            Spacer(minLength: 2)
            if reveal {
                TransportControls(size: 10, playSize: 12, spacing: 0)
            } else {
                PlayPauseButton(size: 12)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        // Lift the row so the progress line sits below the artist name, not through it.
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            ProgressBar(height: 2, interactive: false)
                .padding(.leading, 42)
                .padding(.trailing, 20)
                .padding(.bottom, 1)
        }
    }
}

struct BarLayout: View {
    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(cornerRadius: 8).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 6) {
                TrackLabels(titleSize: 13)
                ProgressBar(height: 3, showTimes: true)
            }
            TransportControls(size: 12, playSize: 17, spacing: 2)
        }
        .padding(.horizontal, 10)
    }
}

struct CardLayout: View {
    @EnvironmentObject private var spotify: SpotifyController

    var body: some View {
        VStack(spacing: 0) {
            ArtworkView(cornerRadius: 10)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            TrackLabels(titleSize: 15, alignment: .center)
                .padding(.top, 14)
            ProgressBar(height: 4, showTimes: true)
                .padding(.top, 10)
            HStack(spacing: 6) {
                IconButton(symbol: "shuffle", size: 12, tint: spotify.shuffling ? spotify.accent : nil, help: "Shuffle (S)") {
                    spotify.toggleShuffle()
                }
                Spacer()
                TransportControls(size: 15, playSize: 22, spacing: 8)
                Spacer()
                IconButton(symbol: "repeat", size: 12, tint: spotify.repeating ? spotify.accent : nil, help: "Repeat (R)") {
                    spotify.toggleRepeat()
                }
            }
            .padding(.top, 4)
            VolumeSlider()
                .padding(.top, 4)
        }
        .padding(16)
    }
}

/// Just the cover. Controls fade in on hover.
struct ArtLayout: View {
    @Environment(\.revealControls) private var reveal

    var body: some View {
        ZStack(alignment: .bottom) {
            ArtworkView(cornerRadius: 0)
            if reveal {
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                VStack(spacing: 6) {
                    TrackLabels(titleSize: 13, alignment: .center)
                    ProgressBar(height: 3, showTimes: true)
                    TransportControls(size: 13, playSize: 18, spacing: 10)
                }
                .padding(12)
                .transition(.opacity)
            }
        }
    }
}

/// Narrow vertical strip for parking against a screen edge.
struct ColumnLayout: View {
    @EnvironmentObject private var spotify: SpotifyController

    var body: some View {
        VStack(spacing: 10) {
            ArtworkView(cornerRadius: 8)
                .frame(width: 48, height: 48)
                .help(spotify.track.map { "\($0.name) — \($0.artist)" } ?? "")
            TransportControls(size: 12, playSize: 15, spacing: 4, vertical: true)
            ProgressBar(height: 3, interactive: false)
                .frame(width: 40)
        }
        .padding(.vertical, 8)
    }
}

struct ColumnStatus: View {
    @EnvironmentObject private var spotify: SpotifyController

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note").font(.system(size: 16)).foregroundStyle(.white.opacity(0.6))
            IconButton(symbol: "play.fill", size: 12, help: "Start Spotify") {
                if spotify.state == .notRunning { spotify.openSpotify(hidden: true) } else { spotify.playPause() }
            }
        }
    }
}
