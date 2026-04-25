import Foundation

extension SonoicModel {
    var groupControlMembers: [SonosGroupControlMember] {
        let context = activeGroupControlContext
        let memberIDs = context.memberIDs
        let volumeItemsByPlayerID = activeRoomVolumeItemsByPlayerID
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
                volumeItem: volumeItemsByPlayerID[player.id],
                isCoordinator: player.id == context.coordinatorID,
                isActive: player.id == selectedDiscoveredPlayer?.id,
                isMutatingGroup: groupControlMutatingPlayerID == player.id,
                isMutatingVolume: mutatingRoomVolumeIDs.contains(player.id)
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
        guard hasManualSonosHost else {
            roomVolumeState = .idle
            return
        }

        isGroupControlRefreshing = true
        defer {
            isGroupControlRefreshing = false
        }

        await refreshRoomVolumes(showLoading: roomVolumeState.snapshot?.targetID != activeTarget.id)
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

    private var activeRoomVolumeItemsByPlayerID: [String: SonosRoomVolumeItem] {
        guard let snapshot = roomVolumeState.snapshot,
              snapshot.targetID == activeTarget.id
        else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
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
