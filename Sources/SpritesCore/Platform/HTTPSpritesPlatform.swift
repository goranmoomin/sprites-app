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

    private func request(
        _ method: String, _ path: String, query: [URLQueryItem]? = nil, json body: [String: Any]? = nil
    ) -> URLRequest {
        var url = baseURL.appendingPathComponent(path)
        if let query {
            url.append(queryItems: query)
        }
        var request = URLRequest(url: url)
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
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let plain = Date.ISO8601FormatStyle()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = (try? fractional.parse(string)) ?? (try? plain.parse(string)) { return date }
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
                    status: ServiceStatus(wire: $0.status), pid: $0.pid, startedAt: $0.started_at, error: $0.error,
                    restartCount: $0.restart_count, nextRestartAt: $0.next_restart_at)
            }
        )
    }

    private func metadata(from wire: WireSprite) -> SpriteMetadata {
        SpriteMetadata(
            name: wire.name,
            status: SpriteStatus(wire: wire.status),
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

    public func setURLVisibility(sprite: String, _ visibility: URLVisibility) async throws {
        _ = try await send(request(
            "PUT", "/v1/sprites/\(sprite)",
            json: ["url_settings": ["auth": visibility == .public ? "public" : "sprite"]]))
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

    /// The NDJSON progress event shape shared by service upserts and
    /// checkpoint create/restore.
    private struct WireStreamEvent: Decodable {
        var type: String
        var data: String?

        static func decode(_ data: Data) -> WireStreamEvent? {
            try? JSONDecoder().decode(WireStreamEvent.self, from: data)
        }
    }

    /// Streams NDJSON lines from a request as decoded events.
    private func streamNDJSON<E: Sendable>(
        _ request: URLRequest, decode: @escaping @Sendable (Data) -> E?
    ) async throws -> AsyncThrowingStream<E, Error> {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlatformError.api("not an HTTP response")
        }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw PlatformError.unauthorized
        default: throw PlatformError.api("HTTP \(http.statusCode)")
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        guard !line.isEmpty, let event = decode(Data(line.utf8)) else { continue }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func createCheckpoint(on sprite: String, comment: String)
        async throws -> AsyncThrowingStream<CheckpointEvent, Error>
    {
        try await streamNDJSON(
            request("POST", "/v1/sprites/\(sprite)/checkpoint", json: ["comment": comment])
        ) { data in
            WireStreamEvent.decode(data).map { CheckpointEvent(type: $0.type, message: $0.data) }
        }
    }

    public func restoreCheckpoint(on sprite: String, id: String)
        async throws -> AsyncThrowingStream<CheckpointEvent, Error>
    {
        try await streamNDJSON(
            request("POST", "/v1/sprites/\(sprite)/checkpoints/\(id)/restore")
        ) { data in
            WireStreamEvent.decode(data).map { CheckpointEvent(type: $0.type, message: $0.data) }
        }
    }

    public func upsertService(on sprite: String, named name: String, definition: ServiceDefinition)
        async throws -> AsyncThrowingStream<ServiceUpsertEvent, Error>
    {
        var body: [String: Any] = ["cmd": definition.cmd, "args": definition.args]
        if let env = definition.env { body["env"] = env }
        if let dir = definition.dir { body["dir"] = dir }
        if let needs = definition.needs { body["needs"] = needs }
        if let port = definition.httpPort { body["http_port"] = port }
        return try await streamNDJSON(
            request("PUT", "/v1/sprites/\(sprite)/services/\(name)", json: body)
        ) { data in
            WireStreamEvent.decode(data).map { ServiceUpsertEvent(type: $0.type, message: $0.data) }
        }
    }

    public func startService(on sprite: String, named name: String) async throws {
        _ = try await send(request("POST", "/v1/sprites/\(sprite)/services/\(name)/start"))
    }

    public func stopService(on sprite: String, named name: String) async throws {
        _ = try await send(request("POST", "/v1/sprites/\(sprite)/services/\(name)/stop"))
    }

    public func deleteService(on sprite: String, named name: String) async throws {
        _ = try await send(request("DELETE", "/v1/sprites/\(sprite)/services/\(name)"))
    }

    public func serviceLogs(on sprite: String, named name: String, lines: Int) async throws -> String {
        let data = try await send(request(
            "GET", "/v1/sprites/\(sprite)/services/\(name)/logs",
            query: [URLQueryItem(name: "lines", value: String(lines))]))
        return String(decoding: data, as: UTF8.self)
    }

    public func fileExists(on sprite: String, path: String) async throws -> Bool {
        try await runCapturing(on: sprite, ["test", "-e", path]).exitCode == 0
    }

    public func readFile(on sprite: String, path: String) async throws -> String? {
        let result = try await runCapturing(on: sprite, ["cat", path])
        return result.exitCode == 0 ? result.stdoutText : nil
    }

    public func writeFile(on sprite: String, path: String, content: String) async throws {
        let directory = (path as NSString).deletingLastPathComponent
        let session = try await exec(
            on: sprite, command: ExecCommand(["sh", "-c", "mkdir -p \"\(directory)\" && cat > \"\(path)\""]))
        try await session.send(Data(content.utf8))
        try await session.sendEOF()
        for await event in session.events {
            if case .exit(let code) = event, code != 0 {
                throw PlatformError.api("writing \(path) failed with exit \(code)")
            }
        }
    }

    public func upsertTask(on sprite: String, named name: String, expiringInSeconds seconds: Int) async throws {
        let body = "{\"name\":\"\(name)\",\"expire\":\"\(seconds)s\"}"
        let result = try await runCapturing(
            // PUT, not POST: observed live, POST is create-only and 409s on
            // an existing name; PUT creates or refreshes.
            on: sprite, ["sprite-env", "curl", "-s", "-X", "PUT", "-d", body, "/v1/tasks/\(name)"])
        guard result.exitCode == 0 else {
            throw PlatformError.api("upserting task failed: \(result.stdoutText)\(result.stderrText)")
        }
    }

    public func deleteTask(on sprite: String, named name: String) async throws {
        let result = try await runCapturing(
            on: sprite, ["sprite-env", "curl", "-s", "-X", "DELETE", "/v1/tasks/\(name)"])
        guard result.exitCode == 0 else {
            throw PlatformError.api("deleting task failed: \(result.stderrText)")
        }
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

    public func attachExec(on sprite: String, sessionID: String) async throws -> any ExecSession {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/v1/sprites/\(sprite)/exec/\(sessionID)"),
            resolvingAgainstBaseURL: false
        )!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // tty: only TTY sessions survive disconnect (observed live), so an
        // attach target is TTY by construction.
        let session = WebSocketExecSession(session: session, request: request, tty: true)
        // A dead session fails the handshake (observed: 404 under the WS
        // upgrade); throw so callers can tell "gone" from "ended".
        guard await session.sessionID != nil else {
            await session.cancel()
            throw PlatformError.notFound
        }
        return session
    }

    private struct WireExecSession: Decodable {
        var id: String
        var command: String
    }

    private struct WireExecSessionList: Decodable {
        var sessions: [WireExecSession]
    }

    public func listExecSessions(on sprite: String) async throws -> [ExecSessionSummary] {
        let data = try await send(request("GET", "/v1/sprites/\(sprite)/exec"))
        return try Self.decoder.decode(WireExecSessionList.self, from: data).sessions.map {
            ExecSessionSummary(id: $0.id, command: $0.command)
        }
    }

    public func killExecSession(on sprite: String, sessionID: String) async throws {
        // The NDJSON kill-progress body is drained and dropped.
        _ = try await send(request("POST", "/v1/sprites/\(sprite)/exec/\(sessionID)/kill"))
    }
}
