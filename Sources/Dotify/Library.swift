import Foundation

/// Search and recently played, filtered by kind. Recents merge Spotify's history (songs and
/// the playlists they came from) with a local history of everything Dotify saw play,
/// which is the only source for podcast episodes.
@MainActor
final class LibraryStore: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    @Published private(set) var filters: Set<MediaKind>
    @Published private(set) var results: [MediaItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var selection: Int?
    /// False while the Connect form is showing, so Return/arrows go to the form instead of the list.
    var listActive = true
    /// Bumped whenever the panel opens so the search field grabs focus.
    @Published private(set) var focusRequest = 0

    @Published private var remoteRecents: [MediaItem] = []
    @Published private var localRecents: [MediaItem]

    private let api: SpotifyAPI
    private let auth: SpotifyAuth
    private let spotify: SpotifyController
    private var searchTask: Task<Void, Never>?
    private var lastRecentsFetch = Date.distantPast

    private static let historyKey = "localHistory"
    private static let filtersKey = "libraryFilters"
    private static let historyLimit = 150

    init(api: SpotifyAPI, auth: SpotifyAuth, spotify: SpotifyController) {
        self.api = api
        self.auth = auth
        self.spotify = spotify
        let d = UserDefaults.standard
        localRecents = d.data(forKey: Self.historyKey)
            .flatMap { try? JSONDecoder().decode([MediaItem].self, from: $0) } ?? []
        let saved = (d.stringArray(forKey: Self.filtersKey) ?? []).compactMap(MediaKind.init(rawValue:))
        filters = saved.isEmpty ? Set(MediaKind.allCases) : Set(saved)
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// What the list shows right now, in display order.
    var visible: [MediaItem] {
        if isSearching {
            return MediaKind.allCases.filter(filters.contains).flatMap { kind in results.filter { $0.kind == kind } }
        }
        var newest: [String: MediaItem] = [:]
        for item in remoteRecents + localRecents where filters.contains(item.kind) {
            if let existing = newest[item.uri], (existing.playedAt ?? .distantPast) >= (item.playedAt ?? .distantPast) { continue }
            newest[item.uri] = item
        }
        return newest.values.sorted { ($0.playedAt ?? .distantPast) > ($1.playedAt ?? .distantPast) }
    }

    // MARK: - Filters

    func toggle(_ kind: MediaKind) {
        if filters.contains(kind) {
            guard filters.count > 1 else { return }
            filters.remove(kind)
        } else {
            filters.insert(kind)
        }
        UserDefaults.standard.set(filters.map(\.rawValue), forKey: Self.filtersKey)
        selection = nil
        if isSearching { scheduleSearch(debounce: false) }
    }

    /// Option-click a chip to show only that kind.
    func solo(_ kind: MediaKind) {
        filters = [kind]
        UserDefaults.standard.set([kind.rawValue], forKey: Self.filtersKey)
        selection = nil
        if isSearching { scheduleSearch(debounce: false) }
    }

    // MARK: - Loading

    func panelOpened() {
        focusRequest += 1
        selection = nil
        if Date().timeIntervalSince(lastRecentsFetch) > 30 {
            Task { await refreshRecents() }
        }
    }

    func refreshRecents() async {
        guard auth.isConnected else { return }
        lastRecentsFetch = Date()
        do {
            remoteRecents = try await api.recentlyPlayed()
            if !isSearching { errorMessage = nil }
        } catch {
            if !isSearching { errorMessage = error.localizedDescription }
        }
    }

    private func scheduleSearch(debounce: Bool = true) {
        searchTask?.cancel()
        selection = nil
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, auth.isConnected else {
            results = []
            isLoading = false
            errorMessage = nil
            return
        }
        isLoading = true
        let kinds = filters
        searchTask = Task {
            if debounce { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            do {
                let items = try await api.search(q, kinds: kinds)
                guard !Task.isCancelled else { return }
                results = items
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Actions

    func play(_ item: MediaItem) {
        guard item.isShow else {
            spotify.play(uri: item.uri)
            return
        }
        Task {
            do {
                if let episode = try await api.latestEpisode(ofShow: item.uri) {
                    spotify.play(uri: episode)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func moveSelection(_ delta: Int) {
        let count = visible.count
        guard count > 0 else { return }
        selection = min(max((selection ?? -1) + delta, 0), count - 1)
    }

    func playSelection() -> Bool {
        let items = visible
        guard let item = selection.flatMap({ items.indices.contains($0) ? items[$0] : nil }) ?? items.first else { return false }
        play(item)
        return true
    }

    /// Called by SpotifyController whenever a new track or episode starts.
    func record(_ track: Track) {
        let kind: MediaKind
        if track.id.hasPrefix("spotify:track:") {
            kind = .song
        } else if track.id.hasPrefix("spotify:episode:") {
            kind = .podcast
        } else {
            return // ads, local files
        }
        let item = MediaItem(uri: track.id, kind: kind, title: track.name,
                             subtitle: kind == .podcast ? "Episode · \(track.album)" : track.artist,
                             imageURL: track.artworkURL, playedAt: Date())
        localRecents.removeAll { $0.uri == item.uri }
        localRecents.insert(item, at: 0)
        if localRecents.count > Self.historyLimit { localRecents.removeLast(localRecents.count - Self.historyLimit) }
        if let data = try? JSONEncoder().encode(localRecents) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }
}
