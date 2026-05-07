import Foundation

struct SonosControlAPICloudState: Equatable {
    enum Status: Equatable {
        case idle
        case loading
        case verified(SonosControlAPICloudSnapshot)
        case failed(String)
    }

    var status: Status

    static let idle = SonosControlAPICloudState(status: .idle)

    var detail: String? {
        switch status {
        case .idle:
            nil
        case .loading:
            "Checking cloud access"
        case let .verified(snapshot):
            snapshot.summary
        case let .failed(detail):
            detail
        }
    }
}

struct SonosControlAPICloudSnapshot: Equatable {
    var households: [SonosControlAPIHousehold]
    var groupsByHouseholdID: [String: SonosControlAPIGroupSnapshot]

    var groupCount: Int {
        groupsByHouseholdID.values.reduce(0) { $0 + $1.groups.count }
    }

    var playerCount: Int {
        groupsByHouseholdID.values.reduce(0) { $0 + $1.players.count }
    }

    var summary: String {
        [
            "\(households.count) \(households.count == 1 ? "household" : "households")",
            "\(groupCount) \(groupCount == 1 ? "group" : "groups")",
            "\(playerCount) \(playerCount == 1 ? "player" : "players")"
        ].joined(separator: " · ")
    }
}

struct SonosControlAPIHousehold: Decodable, Equatable, Identifiable {
    var id: String
}

struct SonosControlAPIGroupSnapshot: Decodable, Equatable {
    var groups: [SonosControlAPIGroup]
    var players: [SonosControlAPIPlayer]
}

struct SonosControlAPIGroup: Decodable, Equatable, Identifiable {
    var id: String
    var name: String?
    var coordinatorId: String?
    var playbackState: String?
    var playerIds: [String]
}

struct SonosControlAPIPlayer: Decodable, Equatable, Identifiable {
    var id: String
    var name: String?
    var icon: String?
    var webSocketUrl: String?
    var capabilities: [String]?
}
