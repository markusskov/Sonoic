import Foundation

extension SonoicModel {
    private struct QueueRemovalRange {
        let startingIndex: Int
        let numberOfTracks: Int
    }

    var queueRefreshContext: String {
        [
            manualSonosHost,
            activeTarget.id,
            String(describing: activeTarget.kind),
            activeTarget.memberNames.joined(separator: ","),
            nowPlaying.sourceName,
            nowPlaying.title,
            nowPlaying.artistName ?? "",
            nowPlaying.albumTitle ?? ""
        ]
        .joined(separator: "|")
    }

    func refreshQueue(showLoading: Bool = true) async {
        guard hasManualSonosHost else {
            queueState = .idle
            queueDiagnostics = .empty
            isQueueRefreshing = false
            return
        }

        guard !isQueueRefreshing else {
            return
        }

        isQueueRefreshing = true
        defer {
            isQueueRefreshing = false
        }

        if showLoading {
            queueState = .loading
        }

        do {
            let snapshot = queueSnapshotEnrichedFromManualContext(
                try await queueClient.fetchSnapshot(host: manualSonosHost)
            )
            queueDiagnostics = SonosQueueDiagnostics(
                observedAt: Date(),
                currentURI: snapshot.sourceURI ?? nowPlayingDiagnostics.currentURI,
                itemCount: snapshot.items.count,
                lastRefreshErrorDetail: nil,
                lastMutationErrorDetail: queueDiagnostics.lastMutationErrorDetail
            )
            queueState = .loaded(snapshot)
        } catch let error as SonosQueueClient.ClientError {
            queueDiagnostics = SonosQueueDiagnostics(
                observedAt: Date(),
                currentURI: error.currentURI ?? nowPlayingDiagnostics.currentURI,
                itemCount: nil,
                lastRefreshErrorDetail: error.localizedDescription,
                lastMutationErrorDetail: queueDiagnostics.lastMutationErrorDetail
            )
            queueState = .unavailable(error.localizedDescription)
        } catch {
            queueDiagnostics = SonosQueueDiagnostics(
                observedAt: Date(),
                currentURI: nowPlayingDiagnostics.currentURI,
                itemCount: nil,
                lastRefreshErrorDetail: error.localizedDescription,
                lastMutationErrorDetail: queueDiagnostics.lastMutationErrorDetail
            )
            queueState = .failed(error.localizedDescription)
        }
    }

    private func queueSnapshotEnrichedFromManualContext(_ snapshot: SonosQueueSnapshot) -> SonosQueueSnapshot {
        guard let payloads = manualQueueContextPayloads,
              payloads.count == snapshot.items.count
        else {
            return snapshot
        }

        let enrichedItems = zip(snapshot.items, payloads).map { item, payload in
            queueItemEnriched(item, with: payload)
        }

        return SonosQueueSnapshot(
            items: enrichedItems,
            currentItemIndex: snapshot.currentItemIndex,
            sourceURI: snapshot.sourceURI
        )
    }

    private func queueItemEnriched(
        _ item: SonosQueueItem,
        with payload: SonosPlayablePayload
    ) -> SonosQueueItem {
        let payloadSubtitleParts = payload.subtitle?
            .components(separatedBy: "•")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        return SonosQueueItem(
            id: item.id,
            title: item.title == "Unknown Track" ? payload.title : item.title,
            artistName: item.artistName ?? payloadSubtitleParts.first,
            albumTitle: item.albumTitle ?? payloadSubtitleParts.dropFirst().first,
            artworkURL: item.artworkURL ?? payload.artworkURL,
            duration: item.duration ?? payload.duration
        )
    }

    func refreshQueueAfterPlaybackChangeIfNeeded() async {
        guard hasManualSonosHost,
              !isQueueRefreshing,
              !isQueueClearing,
              !isQueueMutating
        else {
            return
        }

        let shouldRefresh: Bool
        switch queueState {
        case .idle, .loading:
            shouldRefresh = selectedTab == .queue
        case .unavailable, .loaded, .failed:
            shouldRefresh = true
        }

        guard shouldRefresh else {
            return
        }

        await refreshQueue(showLoading: false)
    }

    func clearQueue() async -> Bool {
        guard hasManualSonosHost else {
            queueState = .idle
            isQueueClearing = false
            return false
        }

        guard let snapshot = queueState.snapshot,
              snapshot.supportsLocalMutation
        else {
            return recordQueueMutationUnavailable(sourceURI: queueState.snapshot?.sourceURI)
        }

        guard !isQueueClearing, !isQueueRefreshing, !isQueueMutating else {
            return false
        }

        isQueueClearing = true
        defer {
            isQueueClearing = false
        }

        return await performQueueMutation(
            optimisticSnapshot: SonosQueueSnapshot(
                items: [],
                currentItemIndex: nil,
                sourceURI: snapshot.sourceURI
            )
        ) { clearHost in
            try await avTransportClient.removeAllTracksFromQueue(host: clearHost)
        }
    }

    func removeQueueItems(atOffsets offsets: IndexSet) async -> Bool {
        guard let snapshot = queueState.snapshot else {
            return false
        }

        guard snapshot.supportsLocalMutation else {
            return recordQueueMutationUnavailable(sourceURI: snapshot.sourceURI)
        }

        let removalRanges = queueRemovalRanges(for: offsets)
        guard !removalRanges.isEmpty else {
            return false
        }

        return await performQueueMutation(
            optimisticSnapshot: snapshot.removingItems(atOffsets: offsets)
        ) { queueHost in
            for removalRange in removalRanges.reversed() {
                try await avTransportClient.removeTrackRangeFromQueue(
                    host: queueHost,
                    startingIndex: removalRange.startingIndex,
                    numberOfTracks: removalRange.numberOfTracks
                )
            }
        }
    }

    func moveQueueItems(fromOffsets source: IndexSet, toOffset destination: Int) async -> Bool {
        guard let snapshot = queueState.snapshot else {
            return false
        }

        guard snapshot.supportsLocalMutation else {
            return recordQueueMutationUnavailable(sourceURI: snapshot.sourceURI)
        }

        let sourceOffsets = source.sorted()
        guard let firstSourceOffset = sourceOffsets.first,
              sourceOffsets.last.map({ $0 - firstSourceOffset + 1 == sourceOffsets.count }) == true
        else {
            return false
        }

        let nextSnapshot = snapshot.movingItems(fromOffsets: source, toOffset: destination)
        guard nextSnapshot != snapshot else {
            return true
        }

        let insertBefore = min(max(destination + 1, 1), snapshot.items.count + 1)

        return await performQueueMutation(optimisticSnapshot: nextSnapshot) { queueHost in
            try await avTransportClient.reorderTracksInQueue(
                host: queueHost,
                startingIndex: firstSourceOffset + 1,
                numberOfTracks: sourceOffsets.count,
                insertBefore: insertBefore
            )
        }
    }

    func manualSonosCoordinatorHost() async -> String? {
        let normalizedHost = normalizedManualSonosHost(manualSonosHost)

        if let topology = try? await zoneGroupTopologyClient.fetchTopology(host: manualSonosHost),
           let coordinatorHost = topology.coordinatorHost(matchingTargetID: activeTarget.id, host: normalizedHost)
        {
            return coordinatorHost
        }

        return manualSonosHost.sonoicNonEmptyTrimmed
    }

    private func performQueueMutation(
        optimisticSnapshot: SonosQueueSnapshot,
        action: (String) async throws -> Void
    ) async -> Bool {
        guard hasManualSonosHost,
              !isQueueRefreshing,
              !isQueueClearing,
              !isQueueMutating
        else {
            return false
        }

        let previousQueueState = queueState
        queueOperationErrorDetail = nil
        queueDiagnostics.lastMutationErrorDetail = nil
        queueState = .loaded(optimisticSnapshot)
        isQueueMutating = true
        defer {
            isQueueMutating = false
        }

        do {
            let queueHost = await manualSonosCoordinatorHost() ?? manualSonosHost
            try await action(queueHost)
            _ = await syncManualSonosState(showProgress: false)
            await refreshQueue(showLoading: false)
            startManualHostRefreshLoopIfPossible()
            return true
        } catch {
            queueState = previousQueueState
            queueOperationErrorDetail = error.localizedDescription
            queueDiagnostics.lastMutationErrorDetail = error.localizedDescription
            startManualHostRefreshLoopIfPossible()
            return false
        }
    }

    private func queueRemovalRanges(for offsets: IndexSet) -> [QueueRemovalRange] {
        let positions = offsets.map { $0 + 1 }.sorted()
        guard let firstPosition = positions.first else {
            return []
        }

        var removalRanges: [QueueRemovalRange] = []
        var currentStart = firstPosition
        var currentLength = 1

        for position in positions.dropFirst() {
            if position == currentStart + currentLength {
                currentLength += 1
            } else {
                removalRanges.append(
                    QueueRemovalRange(
                        startingIndex: currentStart,
                        numberOfTracks: currentLength
                    )
                )
                currentStart = position
                currentLength = 1
            }
        }

        removalRanges.append(
            QueueRemovalRange(
                startingIndex: currentStart,
                numberOfTracks: currentLength
            )
        )

        return removalRanges
    }

    private func recordQueueMutationUnavailable(sourceURI: String?) -> Bool {
        queueOperationErrorDetail = SonosQueueClient.ClientError
            .unavailableForCurrentSource(currentURI: sourceURI)
            .localizedDescription
        queueDiagnostics.lastMutationErrorDetail = queueOperationErrorDetail
        return false
    }
}
