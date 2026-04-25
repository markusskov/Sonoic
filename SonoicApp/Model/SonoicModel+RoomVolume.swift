import Foundation

extension SonoicModel {
    func refreshRoomVolumes(showLoading: Bool = true) async {
        guard hasManualSonosHost else {
            roomVolumeState = .idle
            return
        }

        guard !isRoomVolumeRefreshInFlight else {
            return
        }

        isRoomVolumeRefreshInFlight = true
        if showLoading {
            roomVolumeState = .loading
        }

        defer {
            isRoomVolumeRefreshInFlight = false
        }

        do {
            let topology = try await zoneGroupTopologyClient.fetchTopology(host: manualSonosHost)
            let normalizedHost = normalizedManualSonosHost(manualSonosHost)

            guard let context = topology.matchedGroupContext(targetID: activeTarget.id, host: normalizedHost) else {
                roomVolumeState = .unavailable("Sonoic couldn't match the selected target to rooms with volume controls.")
                return
            }

            let members = activeTarget.kind == .group ? context.group.members : [context.member]
            let items = await volumeItems(
                for: members,
                coordinatorID: context.group.coordinatorID
            )

            guard !items.isEmpty else {
                roomVolumeState = .unavailable("Sonoic couldn't read volume from any room in this target.")
                return
            }

            roomVolumeState = .loaded(
                SonosRoomVolumeSnapshot(
                    targetID: activeTarget.id,
                    targetName: activeTarget.name,
                    targetKind: activeTarget.kind,
                    items: items,
                    refreshedAt: .now
                )
            )
        } catch {
            roomVolumeState = .failed(error.localizedDescription)
        }
    }

    func setRoomVolume(_ item: SonosRoomVolumeItem, to level: Int) async -> Bool {
        let boundedLevel = min(max(level, 0), 100)
        updateRoomVolumeItem(id: item.id) { roomItem in
            roomItem.volume.level = boundedLevel
        }
        pendingRoomVolumeLevels[item.id] = boundedLevel

        guard !mutatingRoomVolumeIDs.contains(item.id) else {
            return true
        }

        mutatingRoomVolumeIDs.insert(item.id)
        roomVolumeOperationErrorDetail = nil
        var latestRequestSucceeded = true

        while let nextLevel = pendingRoomVolumeLevels[item.id] {
            pendingRoomVolumeLevels[item.id] = nil
            let previousVolume = roomVolumeState.snapshot?.items.first { $0.id == item.id }?.volume

            updateRoomVolumeItem(id: item.id) { roomItem in
                roomItem.volume.level = nextLevel
            }

            do {
                try await renderingControlClient.setVolume(host: item.host, level: nextLevel)
                if normalizedManualSonosHost(item.host) == normalizedManualSonosHost(manualSonosHost) {
                    externalVolume.level = nextLevel
                }
                latestRequestSucceeded = true
            } catch {
                latestRequestSucceeded = false
                if pendingRoomVolumeLevels[item.id] == nil {
                    roomVolumeOperationErrorDetail = error.localizedDescription
                    if let previousVolume {
                        updateRoomVolumeItem(id: item.id) { roomItem in
                            roomItem.volume = previousVolume
                        }
                    } else {
                        await refreshRoomVolumes(showLoading: false)
                    }
                }
            }
        }

        mutatingRoomVolumeIDs.remove(item.id)
        return latestRequestSucceeded
    }

    func toggleRoomMute(_ item: SonosRoomVolumeItem) async {
        let desiredMute = !item.volume.isMuted
        mutatingRoomVolumeIDs.insert(item.id)
        roomVolumeOperationErrorDetail = nil
        updateRoomVolumeItem(id: item.id) { roomItem in
            roomItem.volume.isMuted = desiredMute
        }

        defer {
            mutatingRoomVolumeIDs.remove(item.id)
        }

        do {
            try await renderingControlClient.setMute(host: item.host, isMuted: desiredMute)
            if normalizedManualSonosHost(item.host) == normalizedManualSonosHost(manualSonosHost) {
                externalVolume.isMuted = desiredMute
            }
        } catch {
            roomVolumeOperationErrorDetail = error.localizedDescription
            await refreshRoomVolumes(showLoading: false)
        }
    }

    private func volumeItems(
        for members: [SonosZoneGroupTopology.Member],
        coordinatorID: String
    ) async -> [SonosRoomVolumeItem] {
        await withTaskGroup(of: SonosRoomVolumeItem?.self, returning: [SonosRoomVolumeItem].self) { group in
            for member in members {
                guard let host = member.host.sonoicNonEmptyTrimmed else {
                    continue
                }

                group.addTask { [renderingControlClient] in
                    guard let volume = try? await renderingControlClient.fetchVolume(host: host) else {
                        return nil
                    }

                    return SonosRoomVolumeItem(
                        id: member.id,
                        name: member.name,
                        host: host,
                        isCoordinator: member.id == coordinatorID,
                        volume: volume
                    )
                }
            }

            var items: [SonosRoomVolumeItem] = []
            for await item in group {
                if let item {
                    items.append(item)
                }
            }

            return items.sorted { first, second in
                if first.isCoordinator != second.isCoordinator {
                    return first.isCoordinator
                }

                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            }
        }
    }

    private func updateRoomVolumeItem(
        id: SonosRoomVolumeItem.ID,
        update: (inout SonosRoomVolumeItem) -> Void
    ) {
        guard case var .loaded(snapshot) = roomVolumeState,
              let index = snapshot.items.firstIndex(where: { $0.id == id })
        else {
            return
        }

        update(&snapshot.items[index])
        roomVolumeState = .loaded(snapshot)
    }
}
