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

    private func request(_ method: String, _ path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
        let list = try JSONDecoder().decode(SpriteListResponse.self, from: data)
        return list.sprites.map(metadata(from:))
    }
}
