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
}
