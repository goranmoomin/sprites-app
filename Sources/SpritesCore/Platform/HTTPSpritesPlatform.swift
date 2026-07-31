import Foundation

/// The real Sprites platform client: HTTP against api.sprites.dev with the
/// user's Sprite token as a Bearer credential.
public struct HTTPSpritesPlatform: SpritesPlatform {
    let token: String
    let baseURL: URL
    let session: URLSession

    public init(
        token: String,
        baseURL: URL = URL(string: "https://api.sprites.dev")!,
        session: URLSession = .shared
    ) {
        self.token = token
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: Requests

    private func request(_ method: String, _ path: String, json body: [String: Any]? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlatformError.api("not an HTTP response")
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw PlatformError.unauthorized
        case 404:
            throw PlatformError.notFound
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PlatformError.api("HTTP \(http.statusCode): \(body)")
        }
    }

    // MARK: Wire types

    private struct SpriteListResponse: Decodable {
        var sprites: [WireSprite]
    }

    private struct WireSprite: Decodable {
        var name: String
        var status: String
        var url: URL?
        var url_settings: WireURLSettings?
    }

    private struct WireURLSettings: Decodable {
        var auth: String
    }

    private struct WireService: Decodable {
        var name: String
        var cmd: String
        var args: [String]?
        var env: [String: String]?
        var dir: String?
        var needs: [String]?
        var http_port: Int?
        var state: WireServiceState?
    }

    private struct WireServiceState: Decodable {
        var status: String
        var pid: Int?
        var started_at: Date?
        var error: String?
        var restart_count: Int?
        var next_restart_at: Date?
    }

    private struct WireServiceList: Decodable {
        var services: [WireService]
    }

    private struct WireCheckpoint: Decodable {
        var id: String
        var create_time: Date?
        var comment: String?
        var is_auto: Bool?
    }

    private struct WireTask: Decodable {
        var name: String
        var started_at: Date?
        var expires_at: Date?
    }

    // Observed live: GET /v1/tasks answers {"tasks": [...]}, not a bare array.
    private struct WireTaskList: Decodable {
        var tasks: [WireTask]
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = iso.date(from: string) ?? plain.date(from: string) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "unparseable date \(string)"))
        }
        return decoder
    }()

    private func service(from wire: WireService) -> Service {
        Service(
            name: wire.name, cmd: wire.cmd, args: wire.args ?? [], dir: wire.dir,
            env: wire.env, httpPort: wire.http_port, needs: wire.needs,
            state: wire.state.map {
                ServiceState(
                    status: $0.status, pid: $0.pid, startedAt: $0.started_at, error: $0.error,
                    restartCount: $0.restart_count, nextRestartAt: $0.next_restart_at)
            }
        )
    }

    private func metadata(from wire: WireSprite) -> SpriteMetadata {
        SpriteMetadata(
            name: wire.name,
            status: SpriteStatus(rawValue: wire.status) ?? .cold,
            url: wire.url,
            urlVisibility: wire.url_settings?.auth == "public" ? .public : .private
        )
    }

    // MARK: SpritesPlatform

    public func listSprites() async throws -> [SpriteMetadata] {
        let data = try await send(request("GET", "/v1/sprites"))
        let list = try Self.decoder.decode(SpriteListResponse.self, from: data)
        return list.sprites.map(metadata(from:))
    }

    public func createSprite(named name: String) async throws -> SpriteMetadata {
        let data = try await send(request("POST", "/v1/sprites", json: ["name": name]))
        let wire = try Self.decoder.decode(WireSprite.self, from: data)
        return metadata(from: wire)
    }

    public func deleteSprite(named name: String) async throws {
        _ = try await send(request("DELETE", "/v1/sprites/\(name)"))
    }

    public func getSprite(named name: String) async throws -> SpriteMetadata {
        let data = try await send(request("GET", "/v1/sprites/\(name)"))
        return metadata(from: try Self.decoder.decode(WireSprite.self, from: data))
    }

    public func wake(sprite: String) async throws {
        // Any exec counts as activity and flips the sprite to running.
        _ = try await runCapturing(on: sprite, ["true"])
    }

    public func services(on sprite: String) async throws -> [Service] {
        let data = try await send(request("GET", "/v1/sprites/\(sprite)/services"))
        // The endpoint may answer a bare array or an object wrapper.
        if let list = try? Self.decoder.decode([WireService].self, from: data) {
            return list.map(service(from:))
        }
        return try Self.decoder.decode(WireServiceList.self, from: data).services.map(service(from:))
    }

    public func checkpoints(on sprite: String) async throws -> [Checkpoint] {
        let data = try await send(request("GET", "/v1/sprites/\(sprite)/checkpoints"))
        return try Self.decoder.decode([WireCheckpoint].self, from: data).map {
            Checkpoint(id: $0.id, createTime: $0.create_time, comment: $0.comment, isAuto: $0.is_auto ?? false)
        }
    }

    public func listTasks(on sprite: String) async throws -> [PlatformTask] {
        // The Tasks API is in-sprite only, reached via exec against the
        // management socket.
        let result = try await runCapturing(on: sprite, ["sprite-env", "curl", "-s", "/v1/tasks"])
        guard result.exitCode == 0 else {
            throw PlatformError.api("listing tasks failed: \(result.stderrText)")
        }
        let wire = try Self.decoder.decode(WireTaskList.self, from: result.stdout)
        return wire.tasks.map { PlatformTask(name: $0.name, startedAt: $0.started_at, expiresAt: $0.expires_at) }
    }

    public func exec(on sprite: String, command: ExecCommand) async throws -> any ExecSession {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/v1/sprites/\(sprite)/exec"),
            resolvingAgainstBaseURL: false
        )!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        // URLQueryItem leaves ";" and "&" unencoded in values, and the
        // server splits on them (observed live: a `sh -c` script with ";"
        // arrived truncated). Encode values strictly ourselves.
        var strict = CharacterSet.alphanumerics
        strict.insert(charactersIn: "-._~")
        func encode(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: strict) ?? value
        }
        var pairs = command.argv.map { "cmd=\(encode($0))" }
        pairs.append("stdin=true")
        for (key, value) in command.env.sorted(by: { $0.key < $1.key }) {
            pairs.append("env=\(encode("\(key)=\(value)"))")
        }
        if let dir = command.dir {
            pairs.append("dir=\(encode(dir))")
        }
        if command.tty {
            pairs.append("tty=true")
            if let rows = command.rows { pairs.append("rows=\(rows)") }
            if let cols = command.cols { pairs.append("cols=\(cols)") }
        }
        components.percentEncodedQuery = pairs.joined(separator: "&")
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return WebSocketExecSession(session: session, request: request, tty: command.tty)
    }
}
