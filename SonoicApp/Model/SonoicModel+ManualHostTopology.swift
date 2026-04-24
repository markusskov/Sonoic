import Foundation

extension SonoicModel {
    func refreshManualHostTopologyIfNeeded(force: Bool = false) async {
        guard hasManualSonosHost else {
            manualHostTopologyStatus = .idle
            return
        }

        let normalizedHost = normalizedManualSonosHost(manualSonosHost)
        let hasResolvedCurrentHost = resolvedManualHostTopologyHost == normalizedHost
        let canUseCachedTopology = hasResolvedCurrentHost
            && manualHostTopologyStatus.isResolved
            && !isManualHostTopologyRefreshDue(referenceDate: .now)

        guard force || !canUseCachedTopology else {
            manualHostTopologyStatus = .resolved
            return
        }

        let shouldSurfaceLoading = force || !hasResolvedCurrentHost || manualHostTopologyStatus == .idle
        if shouldSurfaceLoading {
            manualHostTopologyStatus = .loading
        }

        do {
            let topology = try await zoneGroupTopologyClient.fetchTopology(host: manualSonosHost)
            let didApplyTopology = applyManualHostTopologyIfNeeded(topology, host: normalizedHost)

            if didApplyTopology {
                manualHostTopologyLastRefreshAt = .now
                manualHostTopologyStatus = .resolved
            } else {
                manualHostTopologyStatus = .failed("Couldn't match the configured player to a room setup.")
            }
        } catch {
            if shouldSurfaceLoading {
                manualHostTopologyStatus = .failed(error.localizedDescription)
            }
        }
    }

    @discardableResult
    private func applyManualHostTopologyIfNeeded(_ topology: SonosZoneGroupTopology, host: String) -> Bool {
        guard let matchedContext = topology.matchedGroupContext(targetID: activeTarget.id, host: host) else {
            return false
        }

        let matchedGroup = matchedContext.group
        let matchedMember = matchedContext.member
        resolvedManualHostTopologyHost = host

        let nextTarget: SonosActiveTarget
        if matchedGroup.members.count > 1 {
            nextTarget = groupedActiveTarget(from: matchedGroup)
        } else {
            nextTarget = roomActiveTarget(from: matchedMember)
        }

        if nextTarget != activeTarget {
            activeTarget = nextTarget
        }

        return true
    }

    private func groupedActiveTarget(from group: SonosZoneGroupTopology.Group) -> SonosActiveTarget {
        let groupedRoomNames = group.members.compactMap { member in
            member.name.sonoicNonEmptyTrimmed
        }
        let coordinatorName = group.members.first(where: { $0.id == group.coordinatorID })?.name ?? ""

        return SonosActiveTarget(
            id: group.id,
            name: SonosDiscoveredGroup.displayName(for: groupedRoomNames),
            householdName: coordinatorName,
            kind: .group,
            memberNames: groupedRoomNames
        )
    }

    private func roomActiveTarget(from member: SonosZoneGroupTopology.Member) -> SonosActiveTarget {
        let roomID = member.id
        let setupMemberNames = SonosActiveTargetSetupBuilder.memberNames(
            primaryMemberName: member.name,
            satellites: member.satellites
        )
        let bondedAccessories = SonosActiveTargetSetupBuilder.bondedAccessories(
            targetID: roomID,
            satellites: member.satellites
        )
        let roomDetail = selectedDiscoveredPlayer?.modelName ?? activeTarget.householdName

        return SonosActiveTarget(
            id: roomID,
            name: member.name,
            householdName: roomDetail,
            kind: .room,
            memberNames: setupMemberNames,
            bondedAccessories: bondedAccessories
        )
    }

    private func isManualHostTopologyRefreshDue(referenceDate: Date) -> Bool {
        guard let manualHostTopologyLastRefreshAt else {
            return true
        }

        return referenceDate.timeIntervalSince(manualHostTopologyLastRefreshAt) >= Self.manualHostRoomMetadataRefreshInterval
    }
}
