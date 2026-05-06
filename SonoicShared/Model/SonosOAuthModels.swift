import Foundation

nonisolated struct SonosOAuthConfiguration: Equatable, Sendable {
    static let defaultAuthorizationEndpoint = URL(string: "https://api.sonos.com/login/v3/oauth")!
    static let defaultScopes = ["playback-control-all"]

    var clientID: String
    var redirectURI: String
    var callbackScheme: String
    var tokenExchangeURL: URL?
    var tokenRefreshURL: URL?
    var authorizationEndpoint: URL
    var scopes: [String]

    static func load(from bundle: Bundle = .main) -> SonosOAuthConfiguration {
        let clientID = bundle.sonoicOAuthString(for: "SonoicSonosOAuthClientID")
        let redirectURI = bundle.sonoicOAuthString(for: "SonoicSonosOAuthRedirectURI")
        let callbackScheme = bundle.sonoicOAuthString(for: "SonoicSonosOAuthCallbackScheme")
        let tokenExchangeURL = URL(string: bundle.sonoicOAuthString(for: "SonoicSonosOAuthTokenExchangeURL"))
        let tokenRefreshURL = URL(string: bundle.sonoicOAuthString(for: "SonoicSonosOAuthTokenRefreshURL"))
        let authorizationEndpoint = URL(string: bundle.sonoicOAuthString(for: "SonoicSonosOAuthAuthorizationURL"))
            ?? defaultAuthorizationEndpoint
        let scopeString = bundle.sonoicOAuthString(for: "SonoicSonosOAuthScopes")
        let scopes = scopeString
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        return SonosOAuthConfiguration(
            clientID: clientID,
            redirectURI: redirectURI,
            callbackScheme: callbackScheme,
            tokenExchangeURL: tokenExchangeURL,
            tokenRefreshURL: tokenRefreshURL,
            authorizationEndpoint: authorizationEndpoint,
            scopes: scopes.isEmpty ? defaultScopes : scopes
        )
    }

    var isConfigured: Bool {
        !clientID.isEmpty
            && !redirectURI.isEmpty
            && !callbackScheme.isEmpty
            && authorizationEndpoint.scheme == "https"
            && tokenExchangeURL?.scheme == "https"
            && (tokenRefreshURL == nil || tokenRefreshURL?.scheme == "https")
    }

    var scopeValue: String {
        scopes.joined(separator: " ")
    }
}

nonisolated struct SonosOAuthCallback: Equatable, Sendable {
    var exchangeCode: String
    var state: String?
}

nonisolated struct SonosOAuthTokenSet: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var tokenType: String
    var scope: String?
    var expiresAt: Date

    var authorizationHeaderValue: String {
        "\(tokenType) \(accessToken)"
    }

    func isExpired(referenceDate: Date = .now, leeway: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(referenceDate) <= leeway
    }
}

private extension Bundle {
    nonisolated func sonoicOAuthString(for key: String) -> String {
        guard let value = object(forInfoDictionaryKey: key) as? String else {
            return ""
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return ""
        }

        return trimmed
    }
}
