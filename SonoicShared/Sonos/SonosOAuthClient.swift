import Foundation

nonisolated struct SonosOAuthClient: Sendable {
    enum OAuthError: LocalizedError, Equatable, Sendable {
        case notConfigured
        case invalidAuthorizationURL
        case callbackError(String)
        case invalidCallback
        case invalidState
        case missingExchangeCode

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                "Sonos OAuth is not configured."
            case .invalidAuthorizationURL:
                "Sonoic couldn't create the Sonos authorization URL."
            case let .callbackError(error):
                error
            case .invalidCallback:
                "The Sonos sign-in response could not be read."
            case .invalidState:
                "The Sonos sign-in response could not be verified."
            case .missingExchangeCode:
                "The Sonos sign-in response did not include a broker code."
            }
        }
    }

    func authorizationURL(configuration: SonosOAuthConfiguration, state: String) throws -> URL {
        guard configuration.isConfigured else {
            throw OAuthError.notConfigured
        }

        guard var components = URLComponents(url: configuration.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw OAuthError.invalidAuthorizationURL
        }

        components.percentEncodedQuery = [
            ("client_id", configuration.clientID),
            ("response_type", "code"),
            ("state", state),
            ("scope", configuration.scopeValue),
            ("redirect_uri", configuration.redirectURI),
        ]
        .map { name, value in "\(name)=\(Self.percentEncodedQueryValue(value))" }
        .joined(separator: "&")

        guard let url = components.url else {
            throw OAuthError.invalidAuthorizationURL
        }

        return url
    }

    func parseCallbackURL(_ url: URL, expectedState: String) throws -> SonosOAuthCallback {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        var values: [String: String] = [:]
        for queryItem in queryItems {
            guard values[queryItem.name] == nil else {
                throw OAuthError.invalidCallback
            }

            values[queryItem.name] = queryItem.value ?? ""
        }

        if let error = values["error"], !error.isEmpty {
            throw OAuthError.callbackError(values["error_description"] ?? error)
        }

        let state = values["state"]
        guard state == expectedState else {
            throw OAuthError.invalidState
        }

        let exchangeCode = values["broker_code"]
            ?? values["exchange_code"]
            ?? values["code"]

        guard let exchangeCode, !exchangeCode.isEmpty else {
            throw OAuthError.missingExchangeCode
        }

        return SonosOAuthCallback(exchangeCode: exchangeCode, state: state)
    }

    func makeState() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    private static func percentEncodedQueryValue(_ value: String) -> String {
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: ":#[]@!$&'()*+,;=/?")
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
    }
}
