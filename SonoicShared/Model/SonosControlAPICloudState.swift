import Foundation

nonisolated struct SonosControlAPICloudState: Equatable {
    nonisolated enum Status: Equatable {
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

nonisolated struct SonosControlAPICloudSnapshot: Equatable {
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

    func preferredCommandTarget(
        settings: SonosControlAPISettings,
        updatedAt: Date = .now
    ) -> SonosControlAPITargetIdentity? {
        let preferredHouseholdID = settings.selectedHouseholdID?.sonoicNonEmptyTrimmed
        let household = households.first { $0.id == preferredHouseholdID } ?? households.first

        guard let household,
              let groupSnapshot = groupsByHouseholdID[household.id],
              !groupSnapshot.groups.isEmpty
        else {
            return nil
        }

        let preferredGroupID = settings.selectedGroupID?.sonoicNonEmptyTrimmed
        let group = groupSnapshot.groups.first { $0.id == preferredGroupID } ?? groupSnapshot.groups.first
        guard let group else {
            return nil
        }

        return SonosControlAPITargetIdentity(
            householdID: household.id,
            groupID: group.id,
            playerID: group.playerIds.first,
            coordinatorPlayerID: group.coordinatorId,
            updatedAt: updatedAt
        )
    }
}

typealias SonosControlAPIGroupSnapshot = SonosControlAPIGroupsResponse
