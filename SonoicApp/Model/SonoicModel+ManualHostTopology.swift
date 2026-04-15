import Foundation

extension SonoicModel {
    func refreshManualHostTopologyIfNeeded() async {
        guard hasManualSonosHost else {
            return
        }

        let normalizedHost = normalizedManualSonosHost(manualSonosHost)
        guard resolvedManualHostTopologyHost != normalizedHost else {
            return
        }

        guard let topology = try? await zoneGroupTopologyClient.fetchTopology(host: manualSonosHost) else {
            return
        }

        applyManualHostTopologyIfNeeded(topology, host: normalizedHost)
    }

    private func applyManualHostTopologyIfNeeded(_ topology: SonosZoneGroupTopology, host: String) {
        guard let matchedMember = topology.member(matchingTargetID: activeTarget.id, host: host) else {
            return
        }

        resolvedManualHostTopologyHost = host

        let setupMemberNames = deduplicatedSetupMemberNames(
            primaryMemberName: matchedMember.name,
            satelliteNames: matchedMember.satellites.map(\.name)
        )

        var nextTarget = activeTarget
        nextTarget.name = matchedMember.name
        nextTarget.memberNames = setupMemberNames

        guard nextTarget != activeTarget else {
            return
        }

        activeTarget = nextTarget
    }

    private func deduplicatedSetupMemberNames(primaryMemberName: String, satelliteNames: [String]) -> [String] {
        var seenNames: Set<String> = []
        var orderedNames: [String] = []

        for name in [primaryMemberName] + satelliteNames {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                continue
            }

            let normalizedName = trimmedName.lowercased()
            guard !seenNames.contains(normalizedName) else {
                continue
            }

            seenNames.insert(normalizedName)
            orderedNames.append(trimmedName)
        }

        return orderedNames.isEmpty ? [primaryMemberName] : orderedNames
    }
}
