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
    var favoritesByHouseholdID: [String: [SonosControlAPIFavorite]]
    var playlistsByHouseholdID: [String: [SonosControlAPIPlaylist]]

    init(
        households: [SonosControlAPIHousehold],
        groupsByHouseholdID: [String: SonosControlAPIGroupSnapshot],
        favoritesByHouseholdID: [String: [SonosControlAPIFavorite]] = [:],
        playlistsByHouseholdID: [String: [SonosControlAPIPlaylist]] = [:]
    ) {
        self.households = households
        self.groupsByHouseholdID = groupsByHouseholdID
        self.favoritesByHouseholdID = favoritesByHouseholdID
        self.playlistsByHouseholdID = playlistsByHouseholdID
    }

    var groupCount: Int {
        groupsByHouseholdID.values.reduce(0) { $0 + $1.groups.count }
    }

    var playerCount: Int {
        groupsByHouseholdID.values.reduce(0) { $0 + $1.players.count }
    }

    var favoriteCount: Int {
        favoritesByHouseholdID.values.reduce(0) { $0 + $1.count }
    }

    var playlistCount: Int {
        playlistsByHouseholdID.values.reduce(0) { $0 + $1.count }
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

    func uniqueFavorite(
        matchingTitle title: String,
        householdID: String,
        serviceName: String? = nil
    ) -> SonosControlAPIFavorite? {
        let normalizedTitle = title.sonoicControlAPIMatchKey
        guard !normalizedTitle.isEmpty else {
            return nil
        }

        let normalizedServiceName = serviceName?.sonoicControlAPIMatchKey
        let matches = (favoritesByHouseholdID[householdID] ?? []).filter { favorite in
            guard favorite.name.sonoicControlAPIMatchKey == normalizedTitle else {
                return false
            }

            guard let normalizedServiceName else {
                return true
            }

            return favorite.service?.name?.sonoicControlAPIMatchKey == normalizedServiceName
        }

        guard matches.count == 1 else {
            return nil
        }

        return matches[0]
    }

    func uniquePlaylist(
        matchingTitle title: String,
        householdID: String
    ) -> SonosControlAPIPlaylist? {
        uniqueItem(
            matchingTitle: title,
            in: playlistsByHouseholdID[householdID] ?? [],
            title: \.name
        )
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

    private func uniqueItem<Item>(
        matchingTitle title: String,
        in items: [Item],
        title titleKeyPath: KeyPath<Item, String>
    ) -> Item? {
        let normalizedTitle = title.sonoicControlAPIMatchKey
        guard !normalizedTitle.isEmpty else {
            return nil
        }

        let matches = items.filter { $0[keyPath: titleKeyPath].sonoicControlAPIMatchKey == normalizedTitle }
        guard matches.count == 1 else {
            return nil
        }

        return matches[0]
    }
}

typealias SonosControlAPIGroupSnapshot = SonosControlAPIGroupsResponse

private extension String {
    nonisolated var sonoicControlAPIMatchKey: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
