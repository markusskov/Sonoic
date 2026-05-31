import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonosTokenBrokerClientTests {
    @Test
    func exchangeCodePostsBrokerRequestWithoutClientSecret() async throws {
        let recorder = SonosTokenBrokerRequestRecorder()
        let stub = try Self.stubbedClient { request in
            recorder.record(request)
            return try Self.httpResponse(
                for: request,
                statusCode: 200,
                body: """
                {
                    "access_token": "access-1",
                    "refresh_token": "refresh-1",
                    "token_type": "Bearer",
                    "scope": "playback-control-all",
                    "expires_in": 3600
                }
                """
            )
        }
        defer { stub.cleanup() }
        let configuration = try Self.oauthConfiguration(
            tokenExchangeURL: Self.url(for: stub.host, path: "/api/sonos/token"),
            tokenRefreshURL: Self.url(for: stub.host, path: "/api/sonos/token/refresh")
        )

        let tokenSet = try await stub.client.exchangeCode(
            "broker-code-1",
            configuration: configuration,
            state: "state-1"
        )

        #expect(tokenSet.accessToken == "access-1")
        #expect(tokenSet.refreshToken == "refresh-1")
        #expect(tokenSet.tokenType == "Bearer")
        #expect(tokenSet.scope == "playback-control-all")

        let request = try #require(recorder.requests.first)
        #expect(request.url?.path == "/api/sonos/token")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")

        let body = try Self.jsonBody(from: request)
        #expect(body["code"] as? String == "broker-code-1")
        #expect(body["redirect_uri"] as? String == "https://sonos.example.com/oauth/sonos/callback")
        #expect(body["state"] as? String == "state-1")
        #expect(body["client_secret"] == nil)
        #expect(recorder.requests.count == 1)
    }

    @Test
    func refreshTokenPostsBrokerRequestAndDecodesResponse() async throws {
        let recorder = SonosTokenBrokerRequestRecorder()
        let stub = try Self.stubbedClient { request in
            recorder.record(request)
            return try Self.httpResponse(
                for: request,
                statusCode: 200,
                body: """
                {
                    "access_token": "access-2",
                    "expires_in": 3600
                }
                """
            )
        }
        defer { stub.cleanup() }
        let configuration = try Self.oauthConfiguration(
            tokenExchangeURL: Self.url(for: stub.host, path: "/api/sonos/token"),
            tokenRefreshURL: Self.url(for: stub.host, path: "/api/sonos/token/refresh")
        )
        let startedAt = Date()

        let tokenSet = try await stub.client.refreshToken(
            "refresh-1",
            configuration: configuration
        )

        #expect(tokenSet.accessToken == "access-2")
        #expect(tokenSet.refreshToken == nil)
        #expect(tokenSet.tokenType == "Bearer")
        #expect(tokenSet.expiresAt.timeIntervalSince(startedAt) > 3_500)

        let request = try #require(recorder.requests.first)
        #expect(request.url?.path == "/api/sonos/token/refresh")
        #expect(request.httpMethod == "POST")

        let body = try Self.jsonBody(from: request)
        #expect(body["refresh_token"] as? String == "refresh-1")
        #expect(body["client_secret"] == nil)
        #expect(recorder.requests.count == 1)
    }

    @Test
    func brokerHTTPStatusErrorKeepsResponseBodyOutOfDiagnostics() async throws {
        let stub = try Self.stubbedClient { request in
            try Self.httpResponse(
                for: request,
                statusCode: 503,
                body: #"{"error":"temporarily_unavailable","detail":"refresh-token-secret"}"#
            )
        }
        defer { stub.cleanup() }
        let configuration = try Self.oauthConfiguration(
            tokenExchangeURL: Self.url(for: stub.host, path: "/api/sonos/token"),
            tokenRefreshURL: Self.url(for: stub.host, path: "/api/sonos/token/refresh")
        )

        do {
            _ = try await stub.client.refreshToken(
                "refresh-token-secret",
                configuration: configuration
            )
            Issue.record("Expected the broker client to throw an HTTP status error.")
        } catch let error as SonosTokenBrokerClient.BrokerError {
            guard case .httpStatus(503) = error else {
                Issue.record("Expected HTTP 503, got \(error).")
                return
            }

            let description = error.localizedDescription
            #expect(description == "The Sonos token broker returned HTTP 503.")
            #expect(!description.contains("refresh-token-secret"))
            #expect(!description.contains("temporarily_unavailable"))
        } catch {
            Issue.record("Expected a SonosTokenBrokerClient.BrokerError, got \(error).")
        }
    }

    @Test
    func rejectsInsecureBrokerEndpointBeforeNetwork() async throws {
        let recorder = SonosTokenBrokerRequestRecorder()
        let stub = try Self.stubbedClient { request in
            recorder.record(request)
            return try Self.httpResponse(for: request, statusCode: 200)
        }
        defer { stub.cleanup() }
        let configuration = try Self.oauthConfiguration(
            tokenExchangeURL: Self.url(for: stub.host, path: "/api/sonos/token"),
            tokenRefreshURL: try Self.fixtureURL("http://\(stub.host)/api/sonos/token/refresh")
        )

        do {
            _ = try await stub.client.refreshToken("refresh-1", configuration: configuration)
            Issue.record("Expected the broker client to reject the insecure endpoint.")
        } catch let error as SonosTokenBrokerClient.BrokerError {
            guard case .insecureBrokerURL = error else {
                Issue.record("Expected insecureBrokerURL, got \(error).")
                return
            }
        } catch {
            Issue.record("Expected a SonosTokenBrokerClient.BrokerError, got \(error).")
        }

        #expect(recorder.requests.isEmpty)
    }

    private static func stubbedClient(
        responder: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) throws -> (client: SonosTokenBrokerClient, host: String, cleanup: () -> Void) {
        let host = "sonos-token-broker-\(UUID().uuidString).test"
        SonosTokenBrokerURLProtocol.register(host: host, responder: responder)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SonosTokenBrokerURLProtocol.self]

        return (
            SonosTokenBrokerClient(session: URLSession(configuration: configuration)),
            host,
            {
                SonosTokenBrokerURLProtocol.unregister(host: host)
            }
        )
    }

    private static func oauthConfiguration(
        tokenExchangeURL: URL?,
        tokenRefreshURL: URL?
    ) throws -> SonosOAuthConfiguration {
        SonosOAuthConfiguration(
            clientID: "client-1",
            redirectURI: "https://sonos.example.com/oauth/sonos/callback",
            callbackScheme: "sonoic",
            tokenExchangeURL: tokenExchangeURL,
            tokenRefreshURL: tokenRefreshURL,
            authorizationEndpoint: try fixtureURL("https://api.sonos.com/login/v3/oauth"),
            scopes: ["playback-control-all"]
        )
    }

    private static func url(for host: String, path: String) throws -> URL {
        try fixtureURL("https://\(host)\(path)")
    }

    private static func fixtureURL(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    private static func jsonBody(from request: SonosTokenBrokerCapturedRequest) throws -> [String: Any] {
        let body = try #require(request.body)
        let object = try JSONSerialization.jsonObject(with: body)
        return try #require(object as? [String: Any])
    }

    nonisolated private static func httpResponse(
        for request: URLRequest,
        statusCode: Int,
        body: String = "{}"
    ) throws -> (HTTPURLResponse, Data) {
        let url = try #require(request.url)
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (response, Data(body.utf8))
    }
}

private final class SonosTokenBrokerRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedRequests: [SonosTokenBrokerCapturedRequest] = []

    var requests: [SonosTokenBrokerCapturedRequest] {
        lock.withLock {
            capturedRequests
        }
    }

    func record(_ request: URLRequest) {
        let capturedRequest = SonosTokenBrokerCapturedRequest(request)
        lock.withLock {
            capturedRequests.append(capturedRequest)
        }
    }
}

private struct SonosTokenBrokerCapturedRequest: Sendable {
    var url: URL?
    var httpMethod: String?
    var body: Data?

    private var headers: [String: String]

    init(_ request: URLRequest) {
        url = request.url
        httpMethod = request.httpMethod
        body = request.httpBody ?? request.httpBodyStream.map(Self.bodyData)
        headers = Dictionary(
            uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { key, value in
                (key.lowercased(), value)
            }
        )
    }

    func value(forHTTPHeaderField field: String) -> String? {
        headers[field.lowercased()]
    }

    private static func bodyData(from stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            guard bytesRead > 0 else {
                break
            }

            data.append(buffer, count: bytesRead)
        }

        return data.isEmpty ? Data() : data
    }
}

private final class SonosTokenBrokerURLProtocol: URLProtocol {
    private struct Stub: Sendable {
        var responder: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]

    static func register(
        host: String,
        responder: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.withLock {
            stubs[host] = Stub(responder: responder)
        }
    }

    static func unregister(host: String) {
        lock.withLock {
            stubs[host] = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        stub(for: request.url?.host) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let stub = Self.stub(for: request.url?.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try stub.responder(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func stub(for host: String?) -> Stub? {
        guard let host else {
            return nil
        }

        return lock.withLock {
            stubs[host]
        }
    }
}
