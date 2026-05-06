import Foundation

struct SonosControlAPITransport {
    enum TransportError: LocalizedError, Equatable {
        case invalidPath
        case invalidResponse
        case httpStatus(Int, String?)

        var errorDescription: String? {
            switch self {
            case .invalidPath:
                return "The Sonos Control API path is invalid."
            case .invalidResponse:
                return "Sonos returned an unreadable Control API response."
            case let .httpStatus(statusCode, detail):
                if let detail, !detail.isEmpty {
                    return "Sonos Control API returned HTTP \(statusCode): \(detail)"
                }

                return "Sonos Control API returned HTTP \(statusCode)."
            }
        }
    }

    private let baseURL: URL
    private let urlSession: URLSession
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    init(
        baseURL: URL = URL(string: "https://api.ws.sonos.com/control/api/v1")!,
        urlSession: URLSession = .shared,
        jsonDecoder: JSONDecoder = JSONDecoder(),
        jsonEncoder: JSONEncoder = JSONEncoder()
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.jsonDecoder = jsonDecoder
        self.jsonEncoder = jsonEncoder
    }

    func get<Response: Decodable>(
        _ path: String,
        accessToken: String,
        correlationID: UUID = UUID()
    ) async throws -> Response {
        let request = try makeRequest(
            path: path,
            method: "GET",
            accessToken: accessToken,
            correlationID: correlationID,
            body: Optional<Data>.none
        )
        let data = try await perform(request)
        return try jsonDecoder.decode(Response.self, from: data)
    }

    func post<Request: Encodable>(
        _ path: String,
        accessToken: String,
        correlationID: UUID = UUID(),
        body: Request
    ) async throws {
        let bodyData = try jsonEncoder.encode(body)
        let request = try makeRequest(
            path: path,
            method: "POST",
            accessToken: accessToken,
            correlationID: correlationID,
            body: bodyData
        )
        _ = try await perform(request)
    }

    func post(
        _ path: String,
        accessToken: String,
        correlationID: UUID = UUID()
    ) async throws {
        let request = try makeRequest(
            path: path,
            method: "POST",
            accessToken: accessToken,
            correlationID: correlationID,
            body: nil
        )
        _ = try await perform(request)
    }

    func makeRequest(
        path: String,
        method: String,
        accessToken: String,
        correlationID: UUID,
        body: Data?
    ) throws -> URLRequest {
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedPath.isEmpty else {
            throw TransportError.invalidPath
        }
        let url = trimmedPath
            .split(separator: "/")
            .reduce(baseURL) { partialURL, pathComponent in
                partialURL.appending(path: String(pathComponent))
            }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.httpBody = body
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(correlationID.uuidString, forHTTPHeaderField: "X-Sonos-Corr-Id")
        request.setValue("Sonoic iOS", forHTTPHeaderField: "User-Agent")

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransportError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw TransportError.httpStatus(
                httpResponse.statusCode,
                errorDetail(from: data)
            )
        }

        return data
    }

    private func errorDetail(from data: Data) -> String? {
        if let errorResponse = try? jsonDecoder.decode(SonosControlAPIErrorResponse.self, from: data) {
            return errorResponse.message?.sonoicNonEmptyTrimmed
                ?? errorResponse.reason?.sonoicNonEmptyTrimmed
                ?? errorResponse.errorCode?.sonoicNonEmptyTrimmed
        }

        return String(data: data, encoding: .utf8)?.sonoicNonEmptyTrimmed
    }
}
