import Foundation

struct SonosTokenBrokerClient {
    enum BrokerError: LocalizedError {
        case missingExchangeURL
        case missingRefreshURL
        case insecureBrokerURL
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .missingExchangeURL:
                "The Sonos token exchange endpoint is not configured."
            case .missingRefreshURL:
                "The Sonos token refresh endpoint is not configured."
            case .insecureBrokerURL:
                "The Sonos token broker endpoint must use HTTPS."
            case .invalidResponse:
                "The Sonos token broker returned an unreadable response."
            case let .httpStatus(status):
                "The Sonos token broker returned HTTP \(status)."
            }
        }
    }

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func exchangeCode(
        _ code: String,
        configuration: SonosOAuthConfiguration,
        state: String?
    ) async throws -> SonosOAuthTokenSet {
        guard let tokenExchangeURL = configuration.tokenExchangeURL else {
            throw BrokerError.missingExchangeURL
        }

        return try await send(
            TokenExchangeRequest(
                code: code,
                redirectURI: configuration.redirectURI,
                state: state
            ),
            to: tokenExchangeURL
        )
    }

    func refreshToken(
        _ refreshToken: String,
        configuration: SonosOAuthConfiguration
    ) async throws -> SonosOAuthTokenSet {
        guard let tokenRefreshURL = configuration.tokenRefreshURL else {
            throw BrokerError.missingRefreshURL
        }

        return try await send(
            TokenRefreshRequest(refreshToken: refreshToken),
            to: tokenRefreshURL
        )
    }

    private func send<Request: Encodable>(_ body: Request, to url: URL) async throws -> SonosOAuthTokenSet {
        guard url.scheme == "https" else {
            throw BrokerError.insecureBrokerURL
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrokerError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw BrokerError.httpStatus(httpResponse.statusCode)
        }

        let brokerResponse = try decoder.decode(TokenResponse.self, from: data)
        return brokerResponse.tokenSet
    }
}

private struct TokenExchangeRequest: Encodable {
    var code: String
    var redirectURI: String
    var state: String?
}

private struct TokenRefreshRequest: Encodable {
    var refreshToken: String
}

private struct TokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var tokenType: String?
    var scope: String?
    var expiresIn: TimeInterval?
    var expiresAt: Date?

    var tokenSet: SonosOAuthTokenSet {
        SonosOAuthTokenSet(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType ?? "Bearer",
            scope: scope,
            expiresAt: expiresAt ?? Date().addingTimeInterval(expiresIn ?? 3_600)
        )
    }
}
