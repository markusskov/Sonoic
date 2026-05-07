import Foundation

struct SonosControlAPIClient {
    enum ClientError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Sonos cloud returned an unreadable response."
            case let .httpStatus(status):
                "Sonos cloud returned HTTP \(status)."
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        baseURL: URL = URL(string: "https://api.ws.sonos.com/control/api/v1")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        decoder = JSONDecoder()
    }

    func fetchCloudSnapshot(tokenSet: SonosOAuthTokenSet) async throws -> SonosControlAPICloudSnapshot {
        let householdsResponse: HouseholdsResponse = try await get("households", tokenSet: tokenSet)
        var groupsByHouseholdID: [String: SonosControlAPIGroupSnapshot] = [:]

        for household in householdsResponse.households {
            let groups: SonosControlAPIGroupSnapshot = try await get(
                "households/\(household.id)/groups",
                tokenSet: tokenSet
            )
            groupsByHouseholdID[household.id] = groups
        }

        return SonosControlAPICloudSnapshot(
            households: householdsResponse.households,
            groupsByHouseholdID: groupsByHouseholdID
        )
    }

    private func get<Response: Decodable>(_ path: String, tokenSet: SonosOAuthTokenSet) async throws -> Response {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(tokenSet.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("Sonoic iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw ClientError.httpStatus(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ClientError.invalidResponse
        }
    }
}

private struct HouseholdsResponse: Decodable {
    var households: [SonosControlAPIHousehold]
}
