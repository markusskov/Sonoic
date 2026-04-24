import Foundation

enum SonosActiveTargetSetupBuilder {
    static func memberNames(
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

    static func bondedAccessories(
        targetID: String,
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
                    id: "\(targetID):satellite:\(satellite.id)",
                    name: trimmedName,
                    role: role(for: satellite, nonSubwooferCount: nonSubwooferCount)
                )
            )
        }

        return accessories
    }

    private static func role(
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
