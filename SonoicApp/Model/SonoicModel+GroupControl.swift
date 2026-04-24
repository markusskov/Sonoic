import Foundation

extension SonoicModel {
    var groupControlMembers: [SonosGroupControlMember] {
        let context = activeGroupControlContext
        let memberIDs = context.memberIDs
        let orderedPlayers = discoveredPlayers
            .filter { memberIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsIndex = context.orderedMemberIDs.firstIndex(of: lhs.id) ?? Int.max
                let rhsIndex = context.orderedMemberIDs.firstIndex(of: rhs.id) ?? Int.max
                if lhsIndex == rhsIndex {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhsIndex < rhsIndex
            }

        return orderedPlayers.map { player in
            SonosGroupControlMember(
                player: player,
                volume: roomVolumes[player.id],
                isCoordinator: player.id == context.coordinatorID,
                isActive: player.id == selectedDiscoveredPlayer?.id,
                isMutatingGroup: groupControlMutatingPlayerID == player.id,
                isMutatingVolume: roomVolumeMutatingPlayerID == player.id
            )
        }
    }

    var groupControlOptions: [SonosGroupControlOption] {
        let memberIDs = activeGroupControlContext.memberIDs

        return discoveredPlayers
            .filter { !memberIDs.contains($0.id) }
            .map {
                SonosGroupControlOption(
                    player: $0,
                    isMutating: groupControlMutatingPlayerID == $0.id
                )
            }
    }

    func refreshActiveGroupVolumes() async {
        let players = groupControlMembers.map(\.player)
        guard !players.isEmpty else {
            roomVolumes = [:]
            return
        }

        isGroupControlRefreshing = true
        defer {
            isGroupControlRefreshing = false
        }

        let fetchedVolumes = await withTaskGroup(
            of: (String, SonoicExternalControlState.Volume?).self,
            returning: [String: SonoicExternalControlState.Volume].self
        ) { group in
            for player in players {
                group.addTask { [renderingControlClient] in
                    let volume = try? await renderingControlClient.fetchVolume(host: player.host)
                    return (player.id, volume)
                }
            }

            var volumes: [String: SonoicExternalControlState.Volume] = [:]
            for await (playerID, volume) in group {
                if let volume {
                    volumes[playerID] = volume
                }
            }
            return volumes
        }

        for (playerID, volume) in fetchedVolumes {
            roomVolumes[playerID] = volume
        }
    }

    func addPlayerToActiveGroup(_ player: SonosDiscoveredPlayer) async -> Bool {
        guard groupControlMutatingPlayerID == nil,
              let coordinatorID = activeGroupControlContext.coordinatorID
        else {
            return false
        }

        groupControlMutatingPlayerID = player.id
        groupControlErrorDetail = nil
        defer {
            groupControlMutatingPlayerID = nil
        }

        do {
            try await avTransportClient.joinGroup(host: player.host, coordinatorID: coordinatorID)
            await refreshAfterGroupMembershipChange()
            return true
        } catch {
            groupControlErrorDetail = error.localizedDescription
            startManualHostRefreshLoopIfPossible()
            return false
        }
    }

    func removePlayerFromActiveGroup(_ player: SonosDiscoveredPlayer) async -> Bool {
        guard groupControlMutatingPlayerID == nil,
              player.id != activeGroupControlContext.coordinatorID
        else {
            return false
        }

        groupControlMutatingPlayerID = player.id
        groupControlErrorDetail = nil
        defer {
            groupControlMutatingPlayerID = nil
        }

        do {
            try await avTransportClient.becomeStandaloneGroup(host: player.host)
            await refreshAfterGroupMembershipChange()
            return true
        } catch {
            groupControlErrorDetail = error.localizedDescription
            startManualHostRefreshLoopIfPossible()
            return false
        }
    }

    func toggleRoomMute(_ player: SonosDiscoveredPlayer) async {
        guard let volume = roomVolumes[player.id],
              roomVolumeMutatingPlayerID == nil
        else {
            return
        }

        roomVolumeMutatingPlayerID = player.id
        groupControlErrorDetail = nil
        let desiredMute = !volume.isMuted

        do {
            try await renderingControlClient.setMute(host: player.host, isMuted: desiredMute)
            roomVolumes[player.id]?.isMuted = desiredMute
            roomVolumeMutatingPlayerID = nil
        } catch {
            roomVolumeMutatingPlayerID = nil
            groupControlErrorDetail = error.localizedDescription
        }
    }

    func setRoomVolume(_ player: SonosDiscoveredPlayer, to level: Int) async -> Bool {
        guard roomVolumeMutatingPlayerID == nil else {
            roomVolumes[player.id]?.level = min(max(level, 0), 100)
            return true
        }

        let boundedLevel = min(max(level, 0), 100)
        let previousVolume = roomVolumes[player.id]
        roomVolumes[player.id]?.level = boundedLevel
        roomVolumeMutatingPlayerID = player.id
        groupControlErrorDetail = nil

        do {
            try await renderingControlClient.setVolume(host: player.host, level: boundedLevel)
            roomVolumeMutatingPlayerID = nil
            return true
        } catch {
            if let previousVolume {
                roomVolumes[player.id] = previousVolume
            }
            roomVolumeMutatingPlayerID = nil
            groupControlErrorDetail = error.localizedDescription
            return false
        }
    }

    private var activeGroupControlContext: (
        coordinatorID: String?,
        memberIDs: Set<String>,
        orderedMemberIDs: [String]
    ) {
        if let group = selectedDiscoveredGroup {
            return (
                coordinatorID: group.coordinatorID,
                memberIDs: Set(group.memberIDs),
                orderedMemberIDs: group.memberIDs
            )
        }

        if let player = selectedDiscoveredPlayer {
            return (
                coordinatorID: player.id,
                memberIDs: [player.id],
                orderedMemberIDs: [player.id]
            )
        }

        let activeID = activeTarget.id
        return (
            coordinatorID: activeID.sonoicNonEmptyTrimmed,
            memberIDs: [activeID],
            orderedMemberIDs: [activeID]
        )
    }

    private func refreshAfterGroupMembershipChange() async {
        queueState = .idle
        queueOperationErrorDetail = nil
        isQueueRefreshing = false
        isQueueClearing = false
        isQueueMutating = false
        manualHostTopologyLastRefreshAt = nil
        manualHostIdentityLastRefreshAt = nil

        await refreshSonosDiscoveryNow()
        await refreshManualSonosPlayerState(forceRoomRefresh: true)

        if selectedTab == .queue {
            await refreshQueue(showLoading: false)
        }

        await refreshActiveGroupVolumes()
    }
}
