import Foundation

extension SonoicModel {
    func refreshManualHostTopologyIfNeeded(force: Bool = false) async {
        guard hasManualSonosHost else {
            manualHostTopologyStatus = .idle
            return
        }

        let normalizedHost = normalizedManualSonosHost(manualSonosHost)
        let hasResolvedCurrentHost = resolvedManualHostTopologyHost == normalizedHost
        guard force || !hasResolvedCurrentHost || isManualHostTopologyRefreshDue(referenceDate: .now) else {
            manualHostTopologyStatus = .resolved
            return
        }

        let shouldSurfaceLoading = force || !hasResolvedCurrentHost || !manualHostTopologyStatus.isResolved
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
        guard let matchedMember = topology.member(matchingTargetID: activeTarget.id, host: host) else {
            return false
        }

        resolvedManualHostTopologyHost = host

        let setupMemberNames = setupMemberNames(
            primaryMemberName: matchedMember.name,
            satellites: matchedMember.satellites
        )
        let bondedAccessories = bondedAccessories(from: matchedMember.satellites)

        var nextTarget = activeTarget
        nextTarget.name = matchedMember.name
        nextTarget.memberNames = setupMemberNames
        nextTarget.bondedAccessories = bondedAccessories

        if nextTarget != activeTarget {
            activeTarget = nextTarget
        }

        return true
    }

    private func setupMemberNames(
        primaryMemberName: String,
        satellites: [SonosZoneGroupTopology.Satellite]
    ) -> [String] {
        var orderedNames: [String] = []

        for name in [primaryMemberName] + satellites.map(\.name) {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                continue
            }

            orderedNames.append(trimmedName)
        }

        return orderedNames.isEmpty ? [primaryMemberName] : orderedNames
    }

    private func bondedAccessories(
        from satellites: [SonosZoneGroupTopology.Satellite]
    ) -> [SonosActiveTarget.BondedAccessory] {
        let nonSubwooferCount = satellites.reduce(into: 0) { count, satellite in
            if !satellite.name.localizedCaseInsensitiveContains("sub") {
                count += 1
            }
        }

        var seenSatelliteIDs: Set<String> = []
        var accessories: [SonosActiveTarget.BondedAccessory] = []

        for satellite in satellites {
            let trimmedName = satellite.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                continue
            }

            guard !seenSatelliteIDs.contains(satellite.id) else {
                continue
            }

            seenSatelliteIDs.insert(satellite.id)
            accessories.append(
                SonosActiveTarget.BondedAccessory(
                    id: "\(activeTarget.id):satellite:\(satellite.id)",
                    name: trimmedName,
                    role: bondedAccessoryRole(
                        for: satellite,
                        nonSubwooferCount: nonSubwooferCount
                    )
                )
            )
        }

        return accessories
    }

    private func bondedAccessoryRole(
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

    private func isManualHostTopologyRefreshDue(referenceDate: Date) -> Bool {
        guard let manualHostTopologyLastRefreshAt else {
            return true
        }

        return referenceDate.timeIntervalSince(manualHostTopologyLastRefreshAt) >= Self.manualHostTopologyRefreshInterval
    }
}
