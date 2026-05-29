import Foundation

extension SonoicModel {
    struct SonosControlAPICommandContext {
        var householdID: String?
        var groupID: String
        var accessToken: String
    }

    func activeSonosControlAPIGroupID() -> String? {
        guard sonosPlaybackCommandRoute.routesCommandsToSonosControlAPI else {
            return nil
        }

        return activeSonosControlAPICommandTarget()?.groupID
            ?? sonosControlAPIState.settings.selectedGroupID?.sonoicNonEmptyTrimmed
    }

    func applyVerifiedSonosControlAPICloudSnapshot(_ snapshot: SonosControlAPICloudSnapshot) {
        markSonosControlAPIAuthorizationReady()

        var settings = sonosControlAPIState.settings
        var didChangeSettings = false

        if settings.mode == .off {
            settings.mode = .preferred
            didChangeSettings = true
        }

        if let target = snapshot.preferredCommandTarget(
            settings: settings,
            activeTargetID: activeTarget.id
        ) {
            if settings.selectedHouseholdID != target.householdID {
                settings.selectedHouseholdID = target.householdID
                didChangeSettings = true
            }

            if settings.selectedGroupID != target.groupID {
                settings.selectedGroupID = target.groupID
                didChangeSettings = true
            }

            if let nextActiveTarget = sonosActiveTarget(from: target, snapshot: snapshot) {
                if activeTarget != nextActiveTarget {
                    sonoicPlaybackDebugLog(
                        "cloudSnapshot activeTarget name='\(nextActiveTarget.name)' id=\(sonoicPlaybackDebugID(nextActiveTarget.id)) group=\(sonoicPlaybackDebugID(target.groupID)) household=\(sonoicPlaybackDebugID(target.householdID))"
                    )
                    activeTarget = nextActiveTarget
                }

                if nowPlaying.isIdlePlaceholder {
                    nowPlaying = .connectedIdle(targetName: nextActiveTarget.name)
                }
            }

            manualHostIdentityStatus = .resolved
            manualHostTopologyStatus = .resolved
        }

        if didChangeSettings {
            updateSonosControlAPISettings(settings)
        }
    }

    private func sonosActiveTarget(
        from target: SonosControlAPITargetIdentity,
        snapshot: SonosControlAPICloudSnapshot
    ) -> SonosActiveTarget? {
        guard let groupSnapshot = snapshot.groupsByHouseholdID[target.householdID],
              let group = groupSnapshot.groups.first(where: { $0.id == target.groupID })
        else {
            return nil
        }

        let playersByID = Dictionary(uniqueKeysWithValues: groupSnapshot.players.map { ($0.id, $0) })
        let groupedPlayers = group.playerIds.compactMap { playersByID[$0] }
        let memberNames = groupedPlayers
            .map { player in
                player.roomName?.sonoicNonEmptyTrimmed
                    ?? player.name?.sonoicNonEmptyTrimmed
                    ?? player.id
            }
        let fallbackName = group.name?.sonoicNonEmptyTrimmed
            ?? memberNames.first
            ?? groupedPlayers.first?.name?.sonoicNonEmptyTrimmed
            ?? "Sonos"
        let primaryPlayer = target.coordinatorPlayerID
            .flatMap { playersByID[$0] }
            ?? target.playerID.flatMap { playersByID[$0] }
            ?? groupedPlayers.first
        let localRoomMetadata = localDiscoveredPlayerMatchingCloudRoom(
            roomName: primaryPlayer?.roomName ?? fallbackName,
            productName: primaryPlayer?.name
        )
        let primaryProductName = localRoomMetadata?.modelName?.sonoicNonEmptyTrimmed
            ?? primaryPlayer?.name?.sonoicNonEmptyTrimmed
            ?? primaryPlayer?.roomName?.sonoicNonEmptyTrimmed
            ?? "Sonos"
        let bondedAccessories = localRoomMetadata?.bondedAccessories ?? []
        let kind: SonosActiveTarget.Kind = groupedPlayers.count > 1 ? .group : .room
        let activeTargetID = kind == .group
            ? group.id
            : (primaryPlayer?.id ?? target.playerID ?? group.id)

        return SonosActiveTarget(
            id: activeTargetID,
            name: fallbackName,
            householdName: primaryProductName,
            kind: kind,
            memberNames: memberNames.isEmpty ? [fallbackName] : memberNames,
            bondedAccessories: bondedAccessories
        )
    }

    private func localDiscoveredPlayerMatchingCloudRoom(
        roomName: String?,
        productName: String?
    ) -> SonosDiscoveredPlayer? {
        let normalizedRoomName = roomName?.sonoicNonEmptyTrimmed?.localizedLowercase
        let normalizedProductName = productName?.sonoicNonEmptyTrimmed?.localizedLowercase

        return discoveredPlayers.first { player in
            let discoveredName = player.name.localizedLowercase
            let discoveredModel = player.modelName?.sonoicNonEmptyTrimmed?.localizedLowercase
            return discoveredName == normalizedRoomName
                || discoveredModel == normalizedProductName
        }
    }

    func sonosControlAPICommandContext(
        requiresActiveTargetMatch: Bool = false,
        logPrefix: String? = nil
    ) async -> SonosControlAPICommandContext? {
        guard sonosPlaybackCommandRoute.routesCommandsToSonosControlAPI else {
            return nil
        }

        let commandTarget = activeSonosControlAPICommandTarget(requiresActiveTargetMatch: requiresActiveTargetMatch)
        if requiresActiveTargetMatch && commandTarget == nil {
            return nil
        }

        let groupID = commandTarget?.groupID
            ?? sonosControlAPIState.settings.selectedGroupID?.sonoicNonEmptyTrimmed
        let householdID = commandTarget?.householdID
            ?? sonosControlAPIState.settings.selectedHouseholdID?.sonoicNonEmptyTrimmed

        guard let groupID else {
            return nil
        }

        guard let tokenSet = await validSonosControlAPITokenSetForCommands(logPrefix: logPrefix) else {
            return nil
        }

        return SonosControlAPICommandContext(
            householdID: householdID,
            groupID: groupID,
            accessToken: tokenSet.accessToken
        )
    }

    func activeSonosControlAPICommandTarget(
        requiresActiveTargetMatch: Bool = false
    ) -> SonosControlAPITargetIdentity? {
        guard case let .verified(snapshot) = sonosControlAPICloudState.status else {
            return nil
        }

        if let activeTarget = snapshot.commandTarget(activeTargetID: activeTarget.id) {
            return activeTarget
        }

        guard !requiresActiveTargetMatch else {
            return nil
        }

        guard activeTarget.kind == .group else {
            return nil
        }

        return snapshot.selectedCommandTarget(settings: sonosControlAPIState.settings)
    }
}
