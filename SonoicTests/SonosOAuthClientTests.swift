import Foundation
import Testing
@testable import Sonoic

struct SonosOAuthClientTests {
    @Test
    func buildsAuthorizationURLWithExpectedSonosParameters() throws {
        let configuration = SonosOAuthConfiguration(
            clientID: "client-1",
            redirectURI: "https://sonoic.example.com/oauth/sonos",
            callbackScheme: "sonoic",
            tokenExchangeURL: URL(string: "https://sonoic.example.com/api/sonos/token"),
            tokenRefreshURL: nil,
            authorizationEndpoint: URL(string: "https://api.sonos.com/login/v3/oauth")!,
            scopes: ["playback-control-all"]
        )

        let url = try SonosOAuthClient().authorizationURL(configuration: configuration, state: "state-1")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.scheme == "https")
        #expect(components.host == "api.sonos.com")
        #expect(components.path == "/login/v3/oauth")
        #expect(queryItems["client_id"] == "client-1")
        #expect(queryItems["response_type"] == "code")
        #expect(queryItems["state"] == "state-1")
        #expect(queryItems["scope"] == "playback-control-all")
        #expect(queryItems["redirect_uri"] == "https://sonoic.example.com/oauth/sonos")
        #expect(url.absoluteString.contains("redirect_uri=https://sonoic.example.com/oauth/sonos") == false)
        #expect(url.absoluteString.contains("redirect_uri=https%3A%2F%2Fsonoic.example.com%2Foauth%2Fsonos"))
    }

    @Test
    func parsesBrokerCallbackAndValidatesState() throws {
        let url = URL(string: "sonoic://sonos-auth?broker_code=broker-123&state=state-1")!
        let callback = try SonosOAuthClient().parseCallbackURL(url, expectedState: "state-1")

        #expect(callback.exchangeCode == "broker-123")
        #expect(callback.state == "state-1")
    }

    @Test
    func rejectsCallbackWithWrongState() {
        let url = URL(string: "sonoic://sonos-auth?broker_code=broker-123&state=state-2")!

        #expect(throws: SonosOAuthClient.OAuthError.invalidState) {
            _ = try SonosOAuthClient().parseCallbackURL(url, expectedState: "state-1")
        }
    }

    @Test
    func rejectsCallbackWithDuplicateQueryItems() {
        let url = URL(string: "sonoic://sonos-auth?broker_code=broker-123&state=state-1&state=state-1")!

        #expect(throws: SonosOAuthClient.OAuthError.invalidCallback) {
            _ = try SonosOAuthClient().parseCallbackURL(url, expectedState: "state-1")
        }
    }

    @Test
    func rejectsInsecureTokenRefreshBrokerConfiguration() {
        let configuration = SonosOAuthConfiguration(
            clientID: "client-1",
            redirectURI: "https://sonoic.example.com/oauth/sonos",
            callbackScheme: "sonoic",
            tokenExchangeURL: URL(string: "https://sonoic.example.com/api/sonos/token"),
            tokenRefreshURL: URL(string: "http://sonoic.example.com/api/sonos/token/refresh"),
            authorizationEndpoint: URL(string: "https://api.sonos.com/login/v3/oauth")!,
            scopes: ["playback-control-all"]
        )

        #expect(!configuration.isConfigured)
    }

    @Test
    func rejectsInsecureAuthorizationEndpointConfiguration() {
        let configuration = SonosOAuthConfiguration(
            clientID: "client-1",
            redirectURI: "https://sonoic.example.com/oauth/sonos",
            callbackScheme: "sonoic",
            tokenExchangeURL: URL(string: "https://sonoic.example.com/api/sonos/token"),
            tokenRefreshURL: URL(string: "https://sonoic.example.com/api/sonos/token/refresh"),
            authorizationEndpoint: URL(string: "http://api.sonos.com/login/v3/oauth")!,
            scopes: ["playback-control-all"]
        )

        #expect(!configuration.isConfigured)
    }

    @Test
    func treatsTokenAsExpiredInsideLeeway() {
        let token = SonosOAuthTokenSet(
            accessToken: "access",
            refreshToken: "refresh",
            tokenType: "Bearer",
            scope: "playback-control-all",
            expiresAt: Date(timeIntervalSince1970: 120)
        )

        #expect(token.isExpired(referenceDate: Date(timeIntervalSince1970: 61), leeway: 60))
        #expect(!token.isExpired(referenceDate: Date(timeIntervalSince1970: 30), leeway: 60))
    }
}
