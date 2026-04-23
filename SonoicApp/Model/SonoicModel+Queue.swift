import Foundation

extension SonoicModel {
    var queueRefreshContext: String {
        [
            manualSonosHost,
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
            let snapshot = try await queueClient.fetchSnapshot(host: manualSonosHost)
            queueState = .loaded(snapshot)
        } catch let error as SonosQueueClient.ClientError {
            queueState = .unavailable(error.localizedDescription)
        } catch {
            queueState = .failed(error.localizedDescription)
        }
    }

    func clearQueue() async -> Bool {
        guard hasManualSonosHost else {
            queueState = .idle
            isQueueClearing = false
            return false
        }

        guard !isQueueClearing, !isQueueRefreshing else {
            return false
        }

        isQueueClearing = true
        defer {
            isQueueClearing = false
        }

        do {
            let clearHost = await manualSonosCoordinatorHost() ?? manualSonosHost
            try await avTransportClient.removeAllTracksFromQueue(host: clearHost)
            queueState = .loaded(SonosQueueSnapshot(items: [], currentItemIndex: nil))
            _ = await syncManualSonosState(showProgress: false)
            startManualHostRefreshLoopIfPossible()
            return true
        } catch {
            queueState = .failed(error.localizedDescription)
            startManualHostRefreshLoopIfPossible()
            return false
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
}
