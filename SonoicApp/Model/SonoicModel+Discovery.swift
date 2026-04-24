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

    func refreshSonosDiscoveryNow() async {
        discoveryErrorDetail = nil
        await refreshDiscoveredPlayers(from: discoveredBonjourServices)
    }

    func selectDiscoveredPlayer(_ player: SonosDiscoveredPlayer) async {
        guard selectingDiscoveredPlayerID != player.id else {
            return
        }

        selectingDiscoveredPlayerID = player.id
        defer {
            selectingDiscoveredPlayerID = nil
        }

        let playerGroup = player.groupID.flatMap { groupID in
            discoveredGroups.first { $0.id == groupID }
        }
        let nextHost = playerGroup?.coordinatorHost ?? player.host
        let nextTarget = playerGroup?.activeTargetPlaceholder ?? player.activeTargetPlaceholder

        if manualSonosHost != nextHost {
            manualSonosHost = nextHost
        } else if activeTarget != nextTarget {
            activeTarget = nextTarget
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

        let topologiesByHost = await fetchDiscoveryTopologies(for: resolvedHosts)

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

        let topologies = Array(topologiesByHost.values)
        let directMemberHosts = SonosDiscoverySnapshotBuilder.directMemberHosts(in: topologies)
        let deviceInfoByHost = await fetchDiscoveryDeviceInfo(for: directMemberHosts)

        guard !Task.isCancelled else {
            return
        }

        let snapshot = SonosDiscoverySnapshotBuilder.snapshot(
            topologies: topologies,
            deviceInfoByHost: deviceInfoByHost
        )

        discoveredPlayers = snapshot.players
        discoveredGroups = snapshot.groups
        isSonosDiscoveryRefreshing = false
        lastSonosDiscoveryRefreshAt = .now
    }

    private func fetchDiscoveryTopologies(for hosts: [String]) async -> [String: SonosZoneGroupTopology] {
        await withTaskGroup(
            of: (String, SonosZoneGroupTopology?).self,
            returning: [String: SonosZoneGroupTopology].self
        ) { group in
            for host in hosts {
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
    }

    private func fetchDiscoveryDeviceInfo(for hosts: [String]) async -> [String: SonosDeviceInfo] {
        await withTaskGroup(
            of: (String, SonosDeviceInfo?).self,
            returning: [String: SonosDeviceInfo].self
        ) { group in
            for host in hosts {
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
    }
}
