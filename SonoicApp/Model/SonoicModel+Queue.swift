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
        if sonosControlAPIState.settings.mode.canSendCommands {
            guard !isQueueRefreshing else {
                return
            }

            isQueueRefreshing = true
            defer {
                isQueueRefreshing = false
            }

            guard sonosControlAPIState.canSendCommands else {
                queueDiagnostics = SonosQueueDiagnostics(
                    observedAt: Date(),
                    currentURI: nowPlayingDiagnostics.currentURI,
                    itemCount: nil,
                    lastRefreshErrorDetail: sonosControlAPIQueueUnavailableDetail,
                    lastMutationErrorDetail: queueDiagnostics.lastMutationErrorDetail
                )
                queueState = .unavailable(sonosControlAPIQueueUnavailableDetail)
                return
            }

            if await refreshSonosControlAPICloudQueueSnapshot() {
                return
            }

            queueDiagnostics = SonosQueueDiagnostics(
                observedAt: Date(),
                currentURI: nowPlayingDiagnostics.currentURI,
                itemCount: nil,
                lastRefreshErrorDetail: "Sonoic does not have a confirmed Cloud Queue snapshot for this playback source.",
                lastMutationErrorDetail: queueDiagnostics.lastMutationErrorDetail
            )
            queueState = .unavailable("Queue is unavailable for this Cloud playback source.")
            return
        }

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

    private var sonosControlAPIQueueUnavailableDetail: String {
        switch sonosControlAPIState.authorizationStatus {
        case .expired:
            "Sonos Cloud sign-in has expired."
        case .notConfigured:
            "Sonos Cloud is not connected."
        case .ready:
            sonosControlAPIState.lastErrorDetail ?? "Sonos Cloud is unavailable."
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
        if sonosControlAPIState.settings.mode.canSendCommands {
            await refreshQueue(showLoading: false)
            return
        }

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

    private func refreshSonosControlAPICloudQueueSnapshot() async -> Bool {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudQueueRefresh") else {
            return false
        }

        do {
            async let playbackStatusTask = sonosControlAPIClient.playbackStatus(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
            async let metadataStatusTask = sonosControlAPIClient.playbackMetadata(
                groupID: context.groupID,
                accessToken: context.accessToken
            )

            let playbackStatus = try await playbackStatusTask
            let metadataStatus = try? await metadataStatusTask
            guard restoreSonosControlAPICloudQueueContextIfNeeded(
                groupID: context.groupID,
                queueVersion: playbackStatus.queueVersion
            ) else {
                return false
            }

            if updateSonosControlAPICloudQueueCurrentItem(
                itemIDCandidates: [
                    playbackStatus.itemId,
                    metadataStatus?.currentItem?.id
                ]
            ) {
                return true
            }

            guard let snapshot = sonosControlAPICloudQueueSnapshot(
                currentItemIndex: nil,
                sourceURI: queueState.snapshot?.sourceURI
            ) else {
                return false
            }

            queueDiagnostics = SonosQueueDiagnostics(
                observedAt: Date(),
                currentURI: snapshot.sourceURI ?? nowPlayingDiagnostics.currentURI,
                itemCount: snapshot.items.count,
                lastRefreshErrorDetail: "Cloud Queue is loaded, but Sonos has not confirmed the current item yet.",
                lastMutationErrorDetail: queueDiagnostics.lastMutationErrorDetail
            )
            queueState = .loaded(snapshot)
            return true
        } catch {
            recordSonosControlAPIError(error)
            if isSonosControlAPIAuthorizationFailure(error) {
                sonosControlAPIState.authorizationStatus = .expired
                sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .expired)
                clearSonosControlAPIPlaybackContextAfterAuthorizationLoss()
            }
            return false
        }
    }

    func clearQueue() async -> Bool {
        guard allowsLocalManualTransportCommands else {
            return recordLocalQueueMutationUnavailableInCloudMode()
        }

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
        guard allowsLocalManualTransportCommands else {
            return recordLocalQueueMutationUnavailableInCloudMode()
        }

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
        guard allowsLocalManualTransportCommands else {
            return recordLocalQueueMutationUnavailableInCloudMode()
        }

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
        guard allowsLocalManualTransportCommands else {
            return recordLocalQueueMutationUnavailableInCloudMode()
        }

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

    private func recordLocalQueueMutationUnavailableInCloudMode() -> Bool {
        queueOperationErrorDetail = "Queue edits are unavailable while Sonos Cloud command mode is active."
        queueDiagnostics.lastMutationErrorDetail = queueOperationErrorDetail
        return false
    }

    func clearSonosControlAPICloudQueueContext() {
        sonosControlAPICloudQueueSessionID = nil
        sonosControlAPICloudQueueGroupID = nil
        sonosControlAPICloudQueueVersion = nil
        sonosControlAPICloudQueueItemIDs = nil
        sonosControlAPICloudQueueTracks = nil
        sonosControlAPICloudQueueVersionMismatchLogKey = nil
        sharedStore?.clearCloudQueueSessionContext()
    }

    func persistSonosControlAPICloudQueueContext(groupID: String? = nil) {
        guard let sessionID = sonosControlAPICloudQueueSessionID?.sonoicNonEmptyTrimmed,
              let itemIDs = sonosControlAPICloudQueueItemIDs,
              !itemIDs.isEmpty
        else {
            sharedStore?.clearCloudQueueSessionContext()
            return
        }

        let context = SonosControlAPICloudQueueSessionContext(
            sessionID: sessionID,
            groupID: groupID?.sonoicNonEmptyTrimmed ?? sonosControlAPICloudQueueGroupID?.sonoicNonEmptyTrimmed,
            queueVersion: sonosControlAPICloudQueueVersion?.sonoicNonEmptyTrimmed,
            itemIDs: itemIDs,
            tracks: sonosControlAPICloudQueueTracks ?? [],
            updatedAt: Date()
        )
        guard context.isUsable else {
            sharedStore?.clearCloudQueueSessionContext()
            return
        }

        do {
            try sharedStore?.saveCloudQueueSessionContext(context)
        } catch {
            sonoicPlaybackDebugLog("cloudQueue persistContext failed error='\(error.localizedDescription)'")
        }
    }

    @discardableResult
    func restoreSonosControlAPICloudQueueContextIfNeeded(groupID: String?, queueVersion: String?) -> Bool {
        let normalizedGroupID = groupID?.sonoicNonEmptyTrimmed
        let normalizedQueueVersion = queueVersion?.sonoicNonEmptyTrimmed

        if sonosControlAPICloudQueueSessionID?.sonoicNonEmptyTrimmed != nil,
           sonosControlAPICloudQueueItemIDs?.isEmpty == false
        {
            let inMemoryGroupID = sonosControlAPICloudQueueGroupID?.sonoicNonEmptyTrimmed
            let inMemoryQueueVersion = sonosControlAPICloudQueueVersion?.sonoicNonEmptyTrimmed
            let groupMatches = normalizedGroupID.map { inMemoryGroupID == $0 } ?? true
            if groupMatches {
                if let normalizedQueueVersion,
                   let inMemoryQueueVersion,
                   inMemoryQueueVersion != normalizedQueueVersion
                {
                    logCloudQueueVersionMismatchOnce(
                        source: "keepingMemory",
                        groupID: inMemoryGroupID,
                        storedVersion: inMemoryQueueVersion,
                        currentVersion: normalizedQueueVersion
                    )
                } else {
                    sonosControlAPICloudQueueVersionMismatchLogKey = nil
                }
                return true
            }

            sonoicPlaybackDebugLog(
                "cloudQueue restoreContext clearing staleMemory group=\(sonoicPlaybackDebugID(inMemoryGroupID)) currentGroup=\(sonoicPlaybackDebugID(normalizedGroupID)) version=\(sonoicPlaybackDebugID(inMemoryQueueVersion)) currentVersion=\(sonoicPlaybackDebugID(normalizedQueueVersion))"
            )
            clearSonosControlAPICloudQueueContext()
        }

        guard let context = sharedStore?.loadCloudQueueSessionContext(),
              context.isUsable,
              context.isFresh
        else {
            return false
        }

        if let storedGroupID = context.groupID?.sonoicNonEmptyTrimmed,
           let normalizedGroupID,
           storedGroupID != normalizedGroupID
        {
            sonoicPlaybackDebugLog(
                "cloudQueue restoreContext skipped groupMismatch stored=\(sonoicPlaybackDebugID(storedGroupID)) current=\(sonoicPlaybackDebugID(normalizedGroupID))"
            )
            clearSonosControlAPICloudQueueContext()
            return false
        }

        if let storedQueueVersion = context.queueVersion?.sonoicNonEmptyTrimmed,
           let normalizedQueueVersion,
           storedQueueVersion != normalizedQueueVersion
        {
            logCloudQueueVersionMismatchOnce(
                source: "keepingStored",
                groupID: context.groupID?.sonoicNonEmptyTrimmed,
                storedVersion: storedQueueVersion,
                currentVersion: normalizedQueueVersion
            )
        } else {
            sonosControlAPICloudQueueVersionMismatchLogKey = nil
        }

        sonosControlAPICloudQueueSessionID = context.sessionID
        sonosControlAPICloudQueueGroupID = context.groupID
        sonosControlAPICloudQueueVersion = context.queueVersion
        sonosControlAPICloudQueueItemIDs = context.itemIDs
        sonosControlAPICloudQueueTracks = context.tracks
        sonoicPlaybackDebugLog(
            "cloudQueue restoreContext session=\(sonoicPlaybackDebugID(context.sessionID)) itemCount=\(context.itemIDs.count)"
        )
        return true
    }

    private func logCloudQueueVersionMismatchOnce(
        source: String,
        groupID: String?,
        storedVersion: String,
        currentVersion: String
    ) {
        let logKey = "\(source)|\(groupID ?? "any")|\(storedVersion)|\(currentVersion)"
        guard sonosControlAPICloudQueueVersionMismatchLogKey != logKey else {
            return
        }

        sonosControlAPICloudQueueVersionMismatchLogKey = logKey
        sonoicPlaybackDebugLog(
            "cloudQueue restoreContext \(source) versionChanged stored=\(sonoicPlaybackDebugID(storedVersion)) current=\(sonoicPlaybackDebugID(currentVersion))"
        )
    }

    func sonosControlAPICloudQueueSnapshot(
        currentItemIndex: Int? = nil,
        sourceURI: String? = nil
    ) -> SonosQueueSnapshot? {
        let payloads = manualQueueContextPayloads ?? []
        let tracks = sonosControlAPICloudQueueTracks ?? []
        let itemIDs = sonosControlAPICloudQueueItemIDs
        let itemCount = max(payloads.count, tracks.count, itemIDs?.count ?? 0)

        guard itemCount > 0 else {
            return nil
        }

        let items = (0..<itemCount).map { index in
            let payload = payloads.indices.contains(index) ? payloads[index] : nil
            let track = tracks.indices.contains(index) ? tracks[index] : nil
            let subtitleParts = payload?.subtitle?
                .components(separatedBy: "•")
                .map(\.sonoicTrimmed)
                .filter { !$0.isEmpty } ?? []
            let itemID = itemIDs.flatMap { $0.indices.contains(index) ? $0[index] : nil }
            return SonosQueueItem(
                id: itemID ?? payload?.id ?? "sonoic-cloud-queue-\(index + 1)",
                title: track?.name?.sonoicNonEmptyTrimmed ?? payload?.title ?? "Unknown Track",
                artistName: track?.artist?.name.sonoicNonEmptyTrimmed ?? subtitleParts.first,
                albumTitle: track?.album?.name.sonoicNonEmptyTrimmed ?? subtitleParts.dropFirst().first,
                artworkURL: track?.imageUrl?.sonoicNonEmptyTrimmed ?? payload?.artworkURL,
                duration: track?.durationMillis.map { TimeInterval($0) / 1_000 } ?? payload?.duration
            )
        }

        return SonosQueueSnapshot(
            items: items,
            currentItemIndex: currentItemIndex.flatMap { items.indices.contains($0) ? $0 : nil },
            sourceURI: sourceURI ?? "sonoic-cloud-queue"
        )
    }

    @discardableResult
    func updateSonosControlAPICloudQueueCurrentItem(itemID: String?) -> Bool {
        updateSonosControlAPICloudQueueCurrentItem(itemIDCandidates: [itemID])
    }

    @discardableResult
    func updateSonosControlAPICloudQueueCurrentItem(itemIDCandidates: [String?]) -> Bool {
        guard let currentIndex = sonosControlAPICloudQueueCurrentIndex(
            from: itemIDCandidates
        ),
              let snapshot = sonosControlAPICloudQueueSnapshot(
                currentItemIndex: currentIndex,
                sourceURI: queueState.snapshot?.sourceURI
              )
        else {
            return false
        }

        queueState = .loaded(snapshot)
        queueDiagnostics = SonosQueueDiagnostics(
            observedAt: Date(),
            currentURI: snapshot.sourceURI ?? nowPlayingDiagnostics.currentURI,
            itemCount: snapshot.items.count,
            lastRefreshErrorDetail: nil,
            lastMutationErrorDetail: queueDiagnostics.lastMutationErrorDetail
        )
        return true
    }

    func sonosControlAPICloudQueueCurrentIndex(from itemIDCandidates: [String?]) -> Int? {
        guard let itemIDs = sonosControlAPICloudQueueItemIDs else {
            return nil
        }

        return SonoicSonosControlAPIQueueCurrentIndexResolver.currentIndex(
            itemIDs: itemIDs,
            candidates: itemIDCandidates
        )
    }
}
