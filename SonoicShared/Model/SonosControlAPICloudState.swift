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
        activeTargetID: String? = nil,
        updatedAt: Date = .now
    ) -> SonosControlAPITargetIdentity? {
        let preferredHouseholdID = settings.selectedHouseholdID?.sonoicNonEmptyTrimmed
        let preferredGroupID = settings.selectedGroupID?.sonoicNonEmptyTrimmed
        let activeTargetID = activeTargetID?.sonoicNonEmptyTrimmed

        if let activeTargetID,
           let activeTarget = commandTarget(
               matching: { group in
                   group.id == activeTargetID
                       || group.coordinatorId == activeTargetID
                       || group.playerIds.contains(activeTargetID)
               },
               updatedAt: updatedAt
           )
        {
            return activeTarget
        }

        if let preferredHouseholdID,
           let preferredGroupID,
           let selectedTarget = commandTarget(
               matching: { household, group in
                   household.id == preferredHouseholdID && group.id == preferredGroupID
               },
               updatedAt: updatedAt
           )
        {
            return selectedTarget
        }

        if let preferredGroupID,
           let selectedTarget = commandTarget(
               matching: { group in group.id == preferredGroupID },
               updatedAt: updatedAt
           )
        {
            return selectedTarget
        }

        return commandTarget(matching: { _, _ in true }, updatedAt: updatedAt)
    }

    private func commandTarget(
        matching predicate: (SonosControlAPIGroup) -> Bool,
        updatedAt: Date
    ) -> SonosControlAPITargetIdentity? {
        commandTarget(matching: { _, group in predicate(group) }, updatedAt: updatedAt)
    }

    private func commandTarget(
        matching predicate: (SonosControlAPIHousehold, SonosControlAPIGroup) -> Bool,
        updatedAt: Date
    ) -> SonosControlAPITargetIdentity? {
        for household in households {
            guard let groupSnapshot = groupsByHouseholdID[household.id] else {
                continue
            }

            guard let group = groupSnapshot.groups.first(where: { predicate(household, $0) }) else {
                continue
            }

            return SonosControlAPITargetIdentity(
                householdID: household.id,
                groupID: group.id,
                playerID: group.playerIds.first,
                coordinatorPlayerID: group.coordinatorId,
                updatedAt: updatedAt
            )
        }

        return nil
    }
}

typealias SonosControlAPIGroupSnapshot = SonosControlAPIGroupsResponse
