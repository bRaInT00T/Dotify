import Foundation

enum MediaKind: String, CaseIterable, Identifiable, Codable {
    case song, playlist, podcast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .song: "Songs"
        case .playlist: "Playlists"
        case .podcast: "Podcasts"
        }
    }

    var symbol: String {
        switch self {
        case .song: "music.note"
        case .playlist: "music.note.list"
        case .podcast: "mic.fill"
        }
    }

    /// Spotify search `type` values this filter covers.
    var searchTypes: [String] {
        switch self {
        case .song: ["track"]
        case .playlist: ["playlist"]
        case .podcast: ["show", "episode"]
        }
    }
}

struct MediaItem: Identifiable, Hashable, Codable {
    var id: String { uri }
    let uri: String
    let kind: MediaKind
    let title: String
    let subtitle: String
    let imageURL: URL?
    var playedAt: Date?

    var isShow: Bool { uri.hasPrefix("spotify:show:") }
}

enum APIError: LocalizedError {
    case http(Int, String?)

    var errorDescription: String? {
        switch self {
        case .http(429, _): "Spotify is rate-limiting requests. Try again in a minute."
        case .http(403, let m): m.map { "Spotify refused the request: \($0)" } ?? "Spotify refused the request. The developer app's owner needs Spotify Premium."
        case .http(let code, let m): m ?? "Spotify request failed (\(code))."
        }
    }
}

/// Thin Spotify Web API client. Development-mode limits apply: search returns at most 10 per type.
@MainActor
final class SpotifyAPI {
    private let auth: SpotifyAuth
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(auth: SpotifyAuth) {
        self.auth = auth
    }

    func search(_ query: String, kinds: Set<MediaKind>) async throws -> [MediaItem] {
        let types = MediaKind.allCases.filter(kinds.contains).flatMap(\.searchTypes)
        let res: SearchResponse = try await get("/search", [
            .init(name: "q", value: query),
            .init(name: "type", value: types.joined(separator: ",")),
            .init(name: "limit", value: "10"),
        ])
        var items: [MediaItem] = []
        items += res.tracks?.items.compactMap { $0?.item } ?? []
        items += res.playlists?.items.compactMap { $0?.item } ?? []
        items += res.shows?.items.compactMap { $0?.item } ?? []
        items += res.episodes?.items.compactMap { $0?.item } ?? []
        return items
    }

    /// Recently played tracks, plus the playlists they were played from.
    func recentlyPlayed() async throws -> [MediaItem] {
        let res: RecentResponse = try await get("/me/player/recently-played", [.init(name: "limit", value: "50")])
        var items: [MediaItem] = []
        var playlistTimes: [String: Date] = [:]
        for entry in res.items {
            let date = Self.parseDate(entry.playedAt)
            var item = entry.track.item
            item.playedAt = date
            items.append(item)
            if let ctx = entry.context, ctx.type == "playlist", playlistTimes[ctx.uri] == nil {
                playlistTimes[ctx.uri] = date
            }
        }
        for (uri, date) in playlistTimes.sorted(by: { $0.value > $1.value }).prefix(10) {
            let id = uri.components(separatedBy: ":").last ?? ""
            if var playlist = try? await playlist(id: id) {
                playlist.playedAt = date
                items.append(playlist)
            }
        }
        return items
    }

    func playlist(id: String) async throws -> MediaItem {
        let p: APIPlaylist = try await get("/playlists/\(id)", [.init(name: "fields", value: "uri,name,images,owner(display_name)")])
        return p.item
    }

    /// Shows can't be played directly, so we play the newest episode.
    func latestEpisode(ofShow uri: String) async throws -> String? {
        let id = uri.components(separatedBy: ":").last ?? ""
        let page: Paging<APIEpisode> = try await get("/shows/\(id)/episodes", [.init(name: "limit", value: "1")])
        return page.items.compactMap { $0 }.first?.uri
    }

    // MARK: - Spotify Connect

    func devices() async throws -> [ConnectDevice] {
        let res: DevicesResponse = try await get("/me/player/devices", [])
        return res.devices.filter { $0.id != nil }
    }

    func transferPlayback(to deviceID: String, play: Bool) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["device_ids": [deviceID], "play": play])
        _ = try await send("PUT", "/me/player", [], body: body)
    }

    func setVolume(_ percent: Int, deviceID: String) async throws {
        _ = try await send("PUT", "/me/player/volume", [
            .init(name: "volume_percent", value: String(min(max(percent, 0), 100))),
            .init(name: "device_id", value: deviceID),
        ])
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String, _ query: [URLQueryItem]) async throws -> T {
        try decoder.decode(T.self, from: try await send("GET", path, query))
    }

    private func send(_ method: String, _ path: String, _ query: [URLQueryItem], body: Data? = nil) async throws -> Data {
        var comps = URLComponents(string: "https://api.spotify.com/v1" + path)!
        comps.queryItems = query.isEmpty ? nil : query
        for attempt in 0..<2 {
            var req = URLRequest(url: comps.url!)
            req.httpMethod = method
            req.setValue("Bearer \(try await auth.validAccessToken())", forHTTPHeaderField: "Authorization")
            if let body {
                req.httpBody = body
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } else if method != "GET" {
                req.setValue("0", forHTTPHeaderField: "Content-Length")
            }
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 && attempt == 0 {
                auth.invalidateAccessToken()
                continue
            }
            guard (200..<300).contains(status) else {
                let message = (try? decoder.decode(APIErrorBody.self, from: data))?.error.message
                throw APIError.http(status, message)
            }
            return data
        }
        throw APIError.http(401, "Spotify sign-in expired. Connect again.")
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

struct ConnectDevice: Identifiable, Decodable, Equatable {
    let id: String?
    let name: String
    let type: String
    let isActive: Bool
    let isRestricted: Bool
    let volumePercent: Int?
    let supportsVolume: Bool?

    var symbol: String {
        switch type.lowercased() {
        case "computer": "laptopcomputer"
        case "smartphone": "iphone"
        case "tablet": "ipad"
        case "tv", "stb": "tv"
        case "avr", "audiodongle": "hifireceiver"
        case "castvideo", "castaudio": "airplayaudio"
        case "gameconsole": "gamecontroller"
        case "automobile": "car"
        default: "hifispeaker"
        }
    }
}

// MARK: - Wire format

private struct DevicesResponse: Decodable {
    let devices: [ConnectDevice]
}

private struct APIErrorBody: Decodable {
    struct Inner: Decodable { let message: String? }
    let error: Inner
}

private struct APIImage: Decodable {
    let url: URL
    let width: Int?
}

/// Smallest image that's still sharp at 2x for a 40pt thumbnail.
private func thumbnail(_ images: [APIImage]?) -> URL? {
    guard let images, !images.isEmpty else { return nil }
    let sorted = images.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
    return (sorted.first { ($0.width ?? 0) >= 120 } ?? sorted.last)?.url
}

private struct Named: Decodable { let name: String }

private struct APIAlbum: Decodable {
    let name: String
    let images: [APIImage]?
}

private struct APITrack: Decodable {
    let uri: String
    let name: String
    let artists: [Named]
    let album: APIAlbum?

    var item: MediaItem {
        MediaItem(uri: uri, kind: .song, title: name,
                  subtitle: artists.map(\.name).joined(separator: ", "),
                  imageURL: thumbnail(album?.images))
    }
}

private struct APIPlaylist: Decodable {
    struct Owner: Decodable { let displayName: String? }
    let uri: String
    let name: String
    let images: [APIImage]?
    let owner: Owner?

    var item: MediaItem {
        MediaItem(uri: uri, kind: .playlist, title: name,
                  subtitle: "Playlist" + (owner?.displayName.map { " · \($0)" } ?? ""),
                  imageURL: thumbnail(images))
    }
}

private struct APIShow: Decodable {
    let uri: String
    let name: String
    let images: [APIImage]?

    var item: MediaItem {
        MediaItem(uri: uri, kind: .podcast, title: name, subtitle: "Podcast", imageURL: thumbnail(images))
    }
}

private struct APIEpisode: Decodable {
    let uri: String
    let name: String
    let images: [APIImage]?
    let releaseDate: String?

    var item: MediaItem {
        MediaItem(uri: uri, kind: .podcast, title: name,
                  subtitle: "Episode" + (releaseDate.map { " · \($0)" } ?? ""),
                  imageURL: thumbnail(images))
    }
}

private struct Paging<T: Decodable>: Decodable {
    // Spotify sometimes returns null entries (e.g. unavailable playlists).
    let items: [T?]
}

private struct SearchResponse: Decodable {
    let tracks: Paging<APITrack>?
    let playlists: Paging<APIPlaylist>?
    let shows: Paging<APIShow>?
    let episodes: Paging<APIEpisode>?
}

private struct RecentResponse: Decodable {
    struct Context: Decodable {
        let type: String
        let uri: String
    }
    struct Entry: Decodable {
        let track: APITrack
        let playedAt: String
        let context: Context?
    }
    let items: [Entry]
}
