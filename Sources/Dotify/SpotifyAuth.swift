import AppKit
import CryptoKit
import Network
import Security

/// Spotify Web API sign-in using Authorization Code + PKCE (no client secret) with a
/// loopback redirect, which is what Spotify requires for desktop apps.
@MainActor
final class SpotifyAuth: ObservableObject {
    static let port: UInt16 = 43821
    static let redirectURI = "http://127.0.0.1:\(port)/callback"
    static let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")!
    private static let scopes = "user-read-recently-played user-read-playback-state user-modify-playback-state"
    private static let playbackScopes: Set<String> = ["user-read-playback-state", "user-modify-playback-state"]
    private static let refreshAccount = "refresh-token"

    @Published var clientID: String {
        didSet { UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespaces), forKey: "spotifyClientID") }
    }
    @Published private(set) var isConnected: Bool
    @Published private(set) var isConnecting = false
    @Published var authError: String?
    /// Scopes the current sign-in actually granted. Sign-ins from before speaker control lack playback scopes.
    @Published private(set) var grantedScopes: Set<String>

    var canControlPlayback: Bool { isConnected && Self.playbackScopes.isSubset(of: grantedScopes) }

    private var accessToken: String?
    private var expiry = Date.distantPast
    private var refreshTask: Task<String, Error>?
    private var server: LoopbackServer?

    init() {
        clientID = UserDefaults.standard.string(forKey: "spotifyClientID") ?? ""
        isConnected = Keychain.get(account: Self.refreshAccount) != nil
        grantedScopes = Set((UserDefaults.standard.string(forKey: "spotifyGrantedScopes") ?? "").split(separator: " ").map(String.init))
    }

    // MARK: - Sign in

    func connect() async {
        let id = clientID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else {
            authError = "Paste your app's Client ID first."
            return
        }
        server?.cancel()
        authError = nil
        isConnecting = true
        defer { isConnecting = false }

        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = Self.randomString(16)

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: id),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: state),
            .init(name: "scope", value: Self.scopes),
        ]

        do {
            let server = LoopbackServer()
            self.server = server
            let callback = server.waitForCallback(port: Self.port)
            NSWorkspace.shared.open(comps.url!)
            let result = try await callback.value
            let items = result.queryItems ?? []
            if let error = items.first(where: { $0.name == "error" })?.value {
                throw AuthError.message(error == "access_denied" ? "Spotify sign-in was cancelled." : "Spotify returned: \(error)")
            }
            guard items.first(where: { $0.name == "state" })?.value == state,
                  let code = items.first(where: { $0.name == "code" })?.value else {
                throw AuthError.message("Unexpected response from Spotify. Try again.")
            }
            let token = try await requestToken([
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": Self.redirectURI,
                "client_id": id,
                "code_verifier": verifier,
            ])
            store(token)
            isConnected = true
        } catch is CancellationError {
            // A newer connect() replaced this one.
        } catch {
            authError = (error as? AuthError)?.text ?? error.localizedDescription
        }
    }

    func disconnect() {
        server?.cancel()
        Keychain.set(nil, account: Self.refreshAccount)
        accessToken = nil
        expiry = .distantPast
        isConnected = false
        grantedScopes = []
        UserDefaults.standard.removeObject(forKey: "spotifyGrantedScopes")
    }

    // MARK: - Tokens

    func validAccessToken() async throws -> String {
        if let accessToken, Date() < expiry { return accessToken }
        if let refreshTask { return try await refreshTask.value }
        guard let refresh = Keychain.get(account: Self.refreshAccount) else { throw AuthError.message("Not connected to Spotify.") }
        let task = Task { () throws -> String in
            do {
                let token = try await requestToken([
                    "grant_type": "refresh_token",
                    "refresh_token": refresh,
                    "client_id": clientID.trimmingCharacters(in: .whitespaces),
                ])
                store(token)
                return token.accessToken
            } catch AuthError.rejected {
                // Refresh token revoked or expired: the user has to sign in again.
                disconnect()
                throw AuthError.message("Spotify sign-in expired. Connect again.")
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    func invalidateAccessToken() {
        accessToken = nil
        expiry = .distantPast
    }

    private func store(_ token: TokenResponse) {
        accessToken = token.accessToken
        expiry = Date().addingTimeInterval(TimeInterval(token.expiresIn - 60))
        if let refresh = token.refreshToken {
            Keychain.set(refresh, account: Self.refreshAccount)
        }
        if let scope = token.scope {
            grantedScopes = Set(scope.split(separator: " ").map(String.init))
            UserDefaults.standard.set(scope, forKey: "spotifyGrantedScopes")
        }
    }

    private func requestToken(_ form: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard status == 200 else {
            let err = try? decoder.decode(TokenError.self, from: data)
            if err?.error == "invalid_grant" { throw AuthError.rejected }
            if err?.error == "invalid_client" {
                throw AuthError.message("Spotify didn't recognize that Client ID.")
            }
            throw AuthError.message(err?.errorDescription ?? "Spotify sign-in failed (\(status)).")
        }
        return try decoder.decode(TokenResponse.self, from: data)
    }

    private static func randomString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?
}

private struct TokenError: Decodable {
    let error: String
    let errorDescription: String?
}

enum AuthError: Error {
    case message(String)
    case rejected

    var text: String {
        switch self {
        case .message(let m): m
        case .rejected: "Spotify rejected the sign-in. Connect again."
        }
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Loopback redirect server

/// Listens on 127.0.0.1 for exactly one `/callback` request from the browser.
final class LoopbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URLComponents, Error>?

    func waitForCallback(port: UInt16) -> Task<URLComponents, Error> {
        Task { @MainActor in
            try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                do {
                    let params = NWParameters.tcp
                    params.allowLocalEndpointReuse = true
                    params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
                    let listener = try NWListener(using: params)
                    self.listener = listener
                    listener.newConnectionHandler = { conn in self.handle(conn) }
                    listener.stateUpdateHandler = { state in
                        if case .failed(let error) = state {
                            self.finish(.failure(AuthError.message("Couldn't listen on port \(port): \(error.localizedDescription)")))
                        }
                    }
                    listener.start(queue: .main)
                } catch {
                    self.finish(.failure(error))
                }
            }
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            guard path.hasPrefix("/callback"), let comps = URLComponents(string: "http://127.0.0.1" + path) else {
                conn.send(content: Self.response(status: "404 Not Found", body: ""), completion: .contentProcessed { _ in conn.cancel() })
                return
            }
            let ok = comps.queryItems?.contains { $0.name == "code" } ?? false
            let body = ok
                ? "<h2>Dotify is connected.</h2><p>You can close this tab.</p>"
                : "<h2>Dotify wasn't connected.</h2><p>Return to the app and try again.</p>"
            conn.send(content: Self.response(status: "200 OK", body: body), completion: .contentProcessed { _ in conn.cancel() })
            self?.finish(.success(comps))
        }
    }

    private func finish(_ result: Result<URLComponents, Error>) {
        listener?.cancel()
        listener = nil
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }

    private static func response(status: String, body: String) -> Data {
        let html = "<!doctype html><meta charset=utf-8><body style=\"font:15px -apple-system;padding:40px;background:#111;color:#eee\">\(body)</body>"
        return Data("HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)".utf8)
    }
}

// MARK: - Keychain

enum Keychain {
    // Tests point this elsewhere so they never touch the real sign-in.
    static var service = "local.dotify"

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
