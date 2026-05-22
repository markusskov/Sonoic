import Foundation

struct SonoicCloudQueueClient {
    enum ClientError: LocalizedError {
        case missingCreateURL
        case insecureCreateURL
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .missingCreateURL:
                "The Sonoic Cloud Queue endpoint is not configured."
            case .insecureCreateURL:
                "The Sonoic Cloud Queue endpoint must use HTTPS."
            case .invalidResponse:
                "The Sonoic Cloud Queue endpoint returned an unreadable response."
            case let .httpStatus(status):
                "The Sonoic Cloud Queue endpoint returned HTTP \(status)."
            }
        }
    }

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    func createQueue(
        _ requestBody: SonoicCloudQueueCreateRequest,
        configuration: SonosOAuthConfiguration
    ) async throws -> SonoicCloudQueueCreateResponse {
        guard let createURL = configuration.cloudQueueCreateURL else {
            throw ClientError.missingCreateURL
        }

        guard createURL.scheme == "https" else {
            throw ClientError.insecureCreateURL
        }

        var request = URLRequest(url: createURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw ClientError.httpStatus(httpResponse.statusCode)
        }

        return try decoder.decode(SonoicCloudQueueCreateResponse.self, from: data)
    }
}

nonisolated struct SonoicCloudQueueCreateRequest: Codable, Equatable {
    var container: SonosControlAPIContainer
    var items: [SonosControlAPIQueueItem]
    var startItemId: String?
}

nonisolated struct SonoicCloudQueueCreateResponse: Codable, Equatable {
    var queueId: String
    var queueBaseUrl: String
    var contextVersion: String
    var queueVersion: String
    var startItemId: String
    var trackMetadata: SonosControlAPITrack?
}
