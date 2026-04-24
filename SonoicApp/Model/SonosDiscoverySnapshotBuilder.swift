import Foundation

struct SonosDiscoverySnapshot {
    let players: [SonosDiscoveredPlayer]
    let groups: [SonosDiscoveredGroup]
}

enum SonosDiscoverySnapshotBuilder {
    static func directMemberHosts(
        in topologies: [SonosZoneGroupTopology]
    ) -> [String] {
        let hosts = topologies.flatMap { topology in
            topology.groups.flatMap { group in
                group.members.compactMap(\.host)
            }
        }

        return Array(Set(hosts)).sorted()
    }

    static func snapshot(
        topologies: [SonosZoneGroupTopology],
        deviceInfoByHost: [String: SonosDeviceInfo]
    ) -> SonosDiscoverySnapshot {
        let membersByID = resolvedMembersByID(in: topologies)
        let groupsByID = resolvedGroupsByID(in: topologies)
        let groups = discoveredGroups(from: groupsByID.values, deviceInfoByHost: deviceInfoByHost)
        let groupByMemberID = groups.reduce(into: [String: SonosDiscoveredGroup]()) { result, group in
            for memberID in group.memberIDs {
                result[memberID] = group
            }
        }
        let players = discoveredPlayers(
            from: membersByID.values,
            deviceInfoByHost: deviceInfoByHost,
            groupByMemberID: groupByMemberID
        )

        return SonosDiscoverySnapshot(players: players, groups: groups)
    }

    private static func resolvedMembersByID(
        in topologies: [SonosZoneGroupTopology]
    ) -> [String: SonosZoneGroupTopology.Member] {
        var membersByID: [String: SonosZoneGroupTopology.Member] = [:]

        for topology in topologies {
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

        return membersByID
    }

    private static func resolvedGroupsByID(
        in topologies: [SonosZoneGroupTopology]
    ) -> [String: SonosZoneGroupTopology.Group] {
        var groupsByID: [String: SonosZoneGroupTopology.Group] = [:]

        for topology in topologies {
            for group in topology.groups {
                if let existingGroup = groupsByID[group.id] {
                    let existingResolvedMembers = resolvedMemberCount(in: existingGroup)
                    let nextResolvedMembers = resolvedMemberCount(in: group)

                    if nextResolvedMembers > existingResolvedMembers {
                        groupsByID[group.id] = group
                    }
                } else {
                    groupsByID[group.id] = group
                }
            }
        }

        return groupsByID
    }

    private static func resolvedMemberCount(in group: SonosZoneGroupTopology.Group) -> Int {
        group.members.reduce(into: 0) { count, member in
            if member.host != nil {
                count += 1
            }
        }
    }

    private static func discoveredGroups(
        from groups: some Sequence<SonosZoneGroupTopology.Group>,
        deviceInfoByHost: [String: SonosDeviceInfo]
    ) -> [SonosDiscoveredGroup] {
        groups.compactMap { group -> SonosDiscoveredGroup? in
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
    }

    private static func discoveredPlayers(
        from members: some Sequence<SonosZoneGroupTopology.Member>,
        deviceInfoByHost: [String: SonosDeviceInfo],
        groupByMemberID: [String: SonosDiscoveredGroup]
    ) -> [SonosDiscoveredPlayer] {
        members.compactMap { member -> SonosDiscoveredPlayer? in
            guard let host = member.host?.sonoicNonEmptyTrimmed else {
                return nil
            }

            let deviceInfo = deviceInfoByHost[host]
            let discoveredGroup = groupByMemberID[member.id]
            let roomName = deviceInfo?.roomName ?? member.name

            return SonosDiscoveredPlayer(
                id: member.id,
                name: roomName,
                host: host,
                modelName: deviceInfo?.playerDetail,
                memberNames: SonosActiveTargetSetupBuilder.memberNames(
                    primaryMemberName: roomName,
                    satellites: member.satellites
                ),
                bondedAccessories: SonosActiveTargetSetupBuilder.bondedAccessories(
                    targetID: member.id,
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
    }
}
