import Foundation

struct SonoicRecentSourceSearch: Identifiable, Codable, Equatable {
    var serviceID: String
    var query: String
    var searchedAt: Date

    var id: String {
        "\(serviceID)-\(query.sonoicTrimmed.lowercased())"
    }
}
