import SwiftUI

enum PlayerLayout: String, CaseIterable, Identifiable {
    case ticker, pill, bar, card, art, column

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ticker: "Ticker"
        case .pill: "Pill"
        case .bar: "Bar"
        case .card: "Card"
        case .art: "Album Art"
        case .column: "Column"
        }
    }

    var symbol: String {
        switch self {
        case .ticker: "text.alignleft"
        case .pill: "capsule"
        case .bar: "rectangle"
        case .card: "rectangle.portrait"
        case .art: "photo"
        case .column: "rectangle.portrait.split.2x1"
        }
    }

    var size: CGSize {
        switch self {
        case .ticker: CGSize(width: 260, height: 26)
        case .pill: CGSize(width: 300, height: 40)
        case .bar: CGSize(width: 420, height: 76)
        case .card: CGSize(width: 280, height: 432)
        case .art: CGSize(width: 220, height: 220)
        case .column: CGSize(width: 64, height: 236)
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .ticker: 13
        case .pill: 20
        case .bar: 14
        case .card: 18
        case .art: 14
        case .column: 14
        }
    }

    /// The column is too narrow for a row of buttons, so its toolbar stacks vertically.
    var toolbarIsVertical: Bool { self == .column }

    var toolbarSize: CGSize {
        toolbarIsVertical ? CGSize(width: size.width, height: 104) : CGSize(width: size.width, height: 32)
    }

    func panelSize(expanded: Bool) -> CGSize {
        expanded ? CGSize(width: size.width, height: size.height + toolbarSize.height) : size
    }

    /// Small layouts show a terse status instead of a full message.
    var isCompact: Bool { self == .ticker || self == .pill || self == .column }

    /// The key that switches to this layout (1–6).
    var shortcut: Character {
        Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1))
    }
}

@MainActor
final class Preferences: ObservableObject {
    private let d = UserDefaults.standard

    @Published var layout: PlayerLayout { didSet { d.set(layout.rawValue, forKey: "layout") } }
    @Published var alwaysOnTop: Bool { didSet { d.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    @Published var opacity: Double { didSet { d.set(opacity, forKey: "opacity") } }
    /// Opacity while the pointer is elsewhere and the player isn't focused. 1.0 turns dimming off.
    @Published var idleOpacity: Double { didSet { d.set(idleOpacity, forKey: "idleOpacity") } }
    @Published var artBackground: Bool { didSet { d.set(artBackground, forKey: "artBackground") } }
    @Published var alwaysShowControls: Bool { didSet { d.set(alwaysShowControls, forKey: "alwaysShowControls") } }
    @Published var showOnAllSpaces: Bool { didSet { d.set(showOnAllSpaces, forKey: "showOnAllSpaces") } }
    @Published var panelVisible: Bool { didSet { d.set(panelVisible, forKey: "panelVisible") } }
    @Published var launchSpotifyOnStart: Bool { didSet { d.set(launchSpotifyOnStart, forKey: "launchSpotifyOnStart") } }
    @Published var quitSpotifyOnExit: Bool { didSet { d.set(quitSpotifyOnExit, forKey: "quitSpotifyOnExit") } }

    init() {
        layout = PlayerLayout(rawValue: d.string(forKey: "layout") ?? "") ?? .bar
        alwaysOnTop = d.object(forKey: "alwaysOnTop") as? Bool ?? true
        opacity = d.object(forKey: "opacity") as? Double ?? 1.0
        idleOpacity = d.object(forKey: "idleOpacity") as? Double ?? 0.5
        artBackground = d.object(forKey: "artBackground") as? Bool ?? true
        alwaysShowControls = d.object(forKey: "alwaysShowControls") as? Bool ?? false
        showOnAllSpaces = d.object(forKey: "showOnAllSpaces") as? Bool ?? true
        panelVisible = d.object(forKey: "panelVisible") as? Bool ?? true
        launchSpotifyOnStart = d.object(forKey: "launchSpotifyOnStart") as? Bool ?? true
        quitSpotifyOnExit = d.object(forKey: "quitSpotifyOnExit") as? Bool ?? true
    }
}
