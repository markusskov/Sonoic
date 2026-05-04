import Foundation
@preconcurrency import MusicKit

extension SonoicMusicKitRequestGate {
    func fetchResourceResponse(
        path: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> AppleMusicLibraryResponse {
        var queryItems = limit.map { [URLQueryItem(name: "limit", value: "\($0)")] } ?? []
        if let offset {
            queryItems.append(URLQueryItem(name: "offset", value: "\(offset)"))
        }

        let response: AppleMusicLibraryResponse = try await fetchDecoded(
            path: path,
            queryItems: queryItems
        )
        return response
    }

    func fetchDecoded<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.music.apple.com"
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let request = MusicDataRequest(urlRequest: URLRequest(url: url))
        let response = try await request.response()
        return try JSONDecoder().decode(Response.self, from: response.data)
    }

    func storefrontCountryCode() async throws -> String {
        if let cachedStorefrontCountryCode {
            return cachedStorefrontCountryCode
        }

        let storefrontCountryCode = try await MusicDataRequest.currentCountryCode
        cachedStorefrontCountryCode = storefrontCountryCode
        return storefrontCountryCode
    }
}
