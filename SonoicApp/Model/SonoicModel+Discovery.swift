import Foundation

extension SonoicModel {
    var hasDiscoveredPlayers: Bool {
        !discoveredPlayers.isEmpty
    }

    var selectedDiscoveredPlayer: SonosDiscoveredPlayer? {
        discoveredPlayer(matchingHost: manualSonosHost)
    }

    var hasDiscoveredGroups: Bool {
        !discoveredGroups.isEmpty
    }

    var selectedDiscoveredGroup: SonosDiscoveredGroup? {
        if activeTarget.kind == .group,
           let matchingGroup = discoveredGroups.first(where: { $0.id == activeTarget.id })
        {
            return matchingGroup
        }

        guard let selectedDiscoveredPlayer,
              let groupID = selectedDiscoveredPlayer.groupID
        else {
            return nil
        }

        return discoveredGroups.first(where: { $0.id == groupID })
    }

    func configureSonosDiscoveryBrowser() {
        sonosDiscoveryBrowser.onServicesChanged = { [weak self] services in
            guard let self else {
                return
            }

            self.discoveredBonjourServices = services
            self.discoveryErrorDetail = nil
            self.scheduleDiscoveredPlayersRefresh()
        }

        sonosDiscoveryBrowser.onFailure = { [weak self] errorDetail in
            guard let self else {
                return
            }

            self.discoveryErrorDetail = errorDetail
        }
    }

    func startSonosDiscoveryIfPossible() {
        guard isSceneActive else {
            return
        }

        discoveryErrorDetail = nil
        sonosDiscoveryBrowser.startBrowsing()

        if !discoveredBonjourServices.isEmpty {
            scheduleDiscoveredPlayersRefresh()
        }
    }

    func stopSonosDiscovery() {
        sonosDiscoveryBrowser.stopBrowsing(clearResults: false)
        discoverySnapshotTask?.cancel()
        discoverySnapshotTask = nil
        isSonosDiscoveryRefreshing = false
    }

    func refreshSonosDiscovery() {
        discoveryErrorDetail = nil
        isSonosDiscoveryRefreshing = true
        sonosDiscoveryBrowser.refresh()
        scheduleDiscoveredPlayersRefresh()
    }

    func selectDiscoveredPlayer(_ player: SonosDiscoveredPlayer) async {
        guard selectingDiscoveredPlayerID != player.id else {
            return
        }

        selectingDiscoveredPlayerID = player.id
        defer {
            selectingDiscoveredPlayerID = nil
        }

        if manualSonosHost != player.host {
            manualSonosHost = player.host
        } else if activeTarget != player.activeTargetPlaceholder {
            activeTarget = player.activeTargetPlaceholder
        }

        await refreshManualSonosPlayerState()
    }

    func selectDiscoveredGroup(_ group: SonosDiscoveredGroup) async {
        guard selectingDiscoveredPlayerID != group.id else {
            return
        }

        selectingDiscoveredPlayerID = group.id
        defer {
            selectingDiscoveredPlayerID = nil
        }

        if manualSonosHost != group.coordinatorHost {
            manualSonosHost = group.coordinatorHost
        }

        if activeTarget != group.activeTargetPlaceholder {
            activeTarget = group.activeTargetPlaceholder
        }

        await refreshManualSonosPlayerState()
    }

    func clearSelectedPlayer() {
        manualSonosHost = ""
    }

    func isDiscoveredPlayerSelected(_ player: SonosDiscoveredPlayer) -> Bool {
        normalizedManualSonosHost(manualSonosHost) == normalizedManualSonosHost(player.host)
    }

    func selectRoomListItem(_ item: SonosRoomListItem) async {
        guard let player = discoveredPlayers.first(where: { $0.id == item.id }) else {
            return
        }

        await selectDiscoveredPlayer(player)
    }

    func discoveredPlayer(matchingHost host: String) -> SonosDiscoveredPlayer? {
        let normalizedHost = normalizedManualSonosHost(host)

        return discoveredPlayers.first {
            normalizedManualSonosHost($0.host) == normalizedHost
        }
    }

    private func scheduleDiscoveredPlayersRefresh() {
        discoverySnapshotTask?.cancel()
        let services = discoveredBonjourServices

        discoverySnapshotTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.refreshDiscoveredPlayers(from: services)
        }
    }

    private func refreshDiscoveredPlayers(from services: [SonosBonjourBrowser.Service]) async {
        let resolvedHosts = Array(Set(services.compactMap(\.host))).sorted()

        guard !resolvedHosts.isEmpty else {
            discoveredPlayers = []
            discoveredGroups = []
            isSonosDiscoveryRefreshing = false
            return
        }

        isSonosDiscoveryRefreshing = true

        let topologiesByHost = await withTaskGroup(
            of: (String, SonosZoneGroupTopology?).self,
            returning: [String: SonosZoneGroupTopology].self
        ) { group in
            for host in resolvedHosts {
                group.addTask { [zoneGroupTopologyClient] in
                    let topology = try? await zoneGroupTopologyClient.fetchTopology(host: host)
                    return (host, topology)
                }
            }

            var topologiesByHost: [String: SonosZoneGroupTopology] = [:]

            for await (host, topology) in group {
                guard let topology else {
                    continue
                }

                topologiesByHost[host] = topology
            }

            return topologiesByHost
        }

        guard !Task.isCancelled else {
            return
        }

        guard !topologiesByHost.isEmpty else {
            discoveredPlayers = []
            discoveredGroups = []
            isSonosDiscoveryRefreshing = false
            lastSonosDiscoveryRefreshAt = .now
            discoveryErrorDetail = "Sonoic found Sonos speakers, but couldn't read their room list yet."
            return
        }

        var membersByID: [String: SonosZoneGroupTopology.Member] = [:]

        for topology in topologiesByHost.values {
            for group in topology.groups {
                for member in group.members {
                    if let existingMember = membersByID[member.id] {
                        if existingMember.host == nil, member.host != nil {
                            membersByID[member.id] = member
                        }
                    } else {
                        membersByID[member.id] = member
                    }
                }
            }
        }

        var groupsByID: [String: SonosZoneGroupTopology.Group] = [:]

        for topology in topologiesByHost.values {
            for group in topology.groups {
                if let existingGroup = groupsByID[group.id] {
                    let existingResolvedMembers = existingGroup.members.reduce(into: 0) { count, member in
                        if member.host != nil {
                            count += 1
                        }
                    }
                    let nextResolvedMembers = group.members.reduce(into: 0) { count, member in
                        if member.host != nil {
                            count += 1
                        }
                    }

                    if nextResolvedMembers > existingResolvedMembers {
                        groupsByID[group.id] = group
                    }
                } else {
                    groupsByID[group.id] = group
                }
            }
        }

        let directMemberHosts = Array(Set(membersByID.values.compactMap(\.host))).sorted()
        let deviceInfoByHost = await withTaskGroup(
            of: (String, SonosDeviceInfo?).self,
            returning: [String: SonosDeviceInfo].self
        ) { group in
            for host in directMemberHosts {
                group.addTask { [deviceInfoClient] in
                    let deviceInfo = try? await deviceInfoClient.fetchDeviceInfo(host: host)
                    return (host, deviceInfo)
                }
            }

            var deviceInfoByHost: [String: SonosDeviceInfo] = [:]

            for await (host, deviceInfo) in group {
                guard let deviceInfo else {
                    continue
                }

                deviceInfoByHost[host] = deviceInfo
            }

            return deviceInfoByHost
        }

        guard !Task.isCancelled else {
            return
        }

        let nextGroups = groupsByID.values.compactMap { group -> SonosDiscoveredGroup? in
            let memberDescriptors = group.members.compactMap { member -> (id: String, name: String, host: String)? in
                guard let host = member.host?.sonoicNonEmptyTrimmed else {
                    return nil
                }

                let resolvedName = deviceInfoByHost[host]?.roomName ?? member.name
                return (id: member.id, name: resolvedName, host: host)
            }

            guard memberDescriptors.count > 1,
                  let coordinatorDescriptor = memberDescriptors.first(where: { $0.id == group.coordinatorID })
            else {
                return nil
            }

            let memberNames = memberDescriptors.map(\.name)

            return SonosDiscoveredGroup(
                id: group.id,
                name: SonosDiscoveredGroup.displayName(for: memberNames),
                coordinatorID: group.coordinatorID,
                coordinatorName: coordinatorDescriptor.name,
                coordinatorHost: coordinatorDescriptor.host,
                memberIDs: memberDescriptors.map(\.id),
                memberNames: memberNames
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        var groupByMemberID: [String: SonosDiscoveredGroup] = [:]
        for group in nextGroups {
            for memberID in group.memberIDs {
                groupByMemberID[memberID] = group
            }
        }

        let nextPlayers = membersByID.values.compactMap { member -> SonosDiscoveredPlayer? in
            guard let host = member.host?.sonoicNonEmptyTrimmed else {
                return nil
            }

            let deviceInfo = deviceInfoByHost[host]
            let discoveredGroup = groupByMemberID[member.id]
            return SonosDiscoveredPlayer(
                id: member.id,
                name: deviceInfo?.roomName ?? member.name,
                host: host,
                modelName: deviceInfo?.playerDetail,
                memberNames: setupMemberNames(
                    primaryMemberName: deviceInfo?.roomName ?? member.name,
                    satellites: member.satellites
                ),
                bondedAccessories: bondedAccessories(
                    for: member.id,
                    satellites: member.satellites
                ),
                groupID: discoveredGroup?.id,
                groupName: discoveredGroup?.name,
                groupMemberNames: discoveredGroup?.memberNames ?? [],
                isGroupCoordinator: discoveredGroup?.coordinatorID == member.id
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        discoveredPlayers = nextPlayers
        discoveredGroups = nextGroups
        isSonosDiscoveryRefreshing = false
        lastSonosDiscoveryRefreshAt = .now
    }

    private func setupMemberNames(
        primaryMemberName: String,
        satellites: [SonosZoneGroupTopology.Satellite]
    ) -> [String] {
        var orderedNames: [String] = []

        for name in [primaryMemberName] + satellites.map(\.name) {
            guard let trimmedName = name.sonoicNonEmptyTrimmed else {
                continue
            }

            orderedNames.append(trimmedName)
        }

        return orderedNames.isEmpty ? [primaryMemberName] : orderedNames
    }

    private func bondedAccessories(
        for playerID: String,
        satellites: [SonosZoneGroupTopology.Satellite]
    ) -> [SonosActiveTarget.BondedAccessory] {
        let nonSubwooferCount = satellites.reduce(into: 0) { count, satellite in
            if !satellite.name.localizedCaseInsensitiveContains("sub") {
                count += 1
            }
        }

        var seenSatelliteIDs: Set<String> = []
        var accessories: [SonosActiveTarget.BondedAccessory] = []

        for satellite in satellites {
            guard let trimmedName = satellite.name.sonoicNonEmptyTrimmed else {
                continue
            }

            guard !seenSatelliteIDs.contains(satellite.id) else {
                continue
            }

            seenSatelliteIDs.insert(satellite.id)
            accessories.append(
                SonosActiveTarget.BondedAccessory(
                    id: "\(playerID):satellite:\(satellite.id)",
                    name: trimmedName,
                    role: discoveredAccessoryRole(
                        for: satellite,
                        nonSubwooferCount: nonSubwooferCount
                    )
                )
            )
        }

        return accessories
    }

    private func discoveredAccessoryRole(
        for satellite: SonosZoneGroupTopology.Satellite,
        nonSubwooferCount: Int
    ) -> SonosActiveTarget.SetupRole {
        if satellite.name.localizedCaseInsensitiveContains("sub") {
            return .subwoofer
        }

        if nonSubwooferCount >= 2 {
            return .surroundSpeaker
        }

        return .bondedProduct
    }
}
