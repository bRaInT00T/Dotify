import XCTest
@testable import Dotify

@MainActor
final class DotifyTests: XCTestCase {
    override func setUp() {
        Keychain.service = "local.dotify.tests"
    }

    func testLoopbackServerReturnsCallbackQuery() async throws {
        let server = LoopbackServer()
        let wait = server.waitForCallback(port: 43899)
        try await Task.sleep(for: .milliseconds(300))
        let (data, resp) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:43899/callback?code=abc&state=xyz")!)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("connected"))
        let comps = try await wait.value
        XCTAssertEqual(comps.queryItems?.first { $0.name == "code" }?.value, "abc")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "state" }?.value, "xyz")
    }

    func testLocalHistoryAndFilters() {
        UserDefaults.standard.removeObject(forKey: "localHistory")
        UserDefaults.standard.removeObject(forKey: "libraryFilters")
        let auth = SpotifyAuth()
        let store = LibraryStore(api: SpotifyAPI(auth: auth), auth: auth, spotify: SpotifyController())
        store.record(Track(id: "spotify:track:1", name: "Song", artist: "A", album: "Alb", artworkURL: nil, duration: 100))
        store.record(Track(id: "spotify:episode:2", name: "Ep", artist: "Show", album: "Show", artworkURL: nil, duration: 100))
        store.record(Track(id: "spotify:ad:3", name: "Ad", artist: "", album: "", artworkURL: nil, duration: 30))
        store.record(Track(id: "spotify:track:1", name: "Song", artist: "A", album: "Alb", artworkURL: nil, duration: 100))

        XCTAssertEqual(store.visible.map(\.uri), ["spotify:track:1", "spotify:episode:2"], "deduped, newest first, ads skipped")

        store.toggle(.song)
        XCTAssertEqual(store.visible.map(\.kind), [.podcast])
        store.toggle(.podcast)
        XCTAssertEqual(store.filters, [.playlist])
        store.toggle(.playlist)
        XCTAssertEqual(store.filters, [.playlist], "can't deselect the last filter")
        store.solo(.song)
        XCTAssertEqual(store.visible.map(\.uri), ["spotify:track:1"])
    }

    func testAudioOutputsIncludeDefault() {
        let outputs = AudioOutputs.all()
        XCTAssertFalse(outputs.isEmpty)
        if let def = AudioOutputs.defaultOutput() {
            XCTAssertTrue(outputs.contains { $0.id == def }, "default output should be listed")
        }
    }

    func testToolbarExpandsUpwardAndCollapsesToSameSpot() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let player = NSRect(x: 900, y: 400, width: 420, height: 76)
        let open = PanelGeometry.windowFrame(player: player, toolbarHeight: 32, visibleFrame: screen)
        XCTAssertEqual(open.toolbar, .init(height: 32, onTop: true))
        XCTAssertEqual(open.frame.minY, player.minY, "player's bottom edge stays put")
        XCTAssertEqual(open.frame.maxY, player.maxY + 32, "toolbar grows upward")
        XCTAssertEqual(PanelGeometry.playerFrame(windowFrame: open.frame, toolbar: open.toolbar), player)
    }

    func testToolbarOpensBelowWhenAgainstTopOfScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let player = NSRect(x: 900, y: 875 - 76 - 10, width: 420, height: 76)
        let open = PanelGeometry.windowFrame(player: player, toolbarHeight: 32, visibleFrame: screen)
        XCTAssertEqual(open.toolbar, .init(height: 32, onTop: false))
        XCTAssertEqual(open.frame.maxY, player.maxY, "player's top edge stays put")
        XCTAssertEqual(PanelGeometry.playerFrame(windowFrame: open.frame, toolbar: open.toolbar), player)
    }
}
