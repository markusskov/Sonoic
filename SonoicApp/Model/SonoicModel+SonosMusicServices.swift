import Foundation

extension SonoicModel {
    func refreshSonosMusicServiceProbe() async {
        guard let host = manualSonosHost.sonoicNonEmptyTrimmed else {
            sonosMusicServiceProbeState = SonosMusicServiceProbeState(
                status: .failed("Choose a room first."),
                snapshot: nil
            )
            return
        }

        sonosMusicServiceProbeState = SonosMusicServiceProbeState(
            status: .loading,
            snapshot: sonosMusicServiceProbeState.snapshot
        )

        do {
            let snapshot = try await musicServicesClient.fetchProbeSnapshot(host: host)
                .includingObservedAccounts(from: observedSonosServiceAccountValues)
            sonosMusicServiceProbeState = SonosMusicServiceProbeState(
                status: .loaded,
                snapshot: snapshot
            )
        } catch {
            sonosMusicServiceProbeState = SonosMusicServiceProbeState(
                status: .failed(error.localizedDescription),
                snapshot: sonosMusicServiceProbeState.snapshot
            )
        }
    }

    private var observedSonosServiceAccountValues: [String?] {
        var values: [String?] = [
            nowPlayingDiagnostics.currentURI,
            nowPlayingDiagnostics.trackURI,
        ]

        if let favorites = homeFavoritesState.snapshot?.items {
            values.append(contentsOf: favorites.map(\.playbackURI))
            values.append(contentsOf: favorites.map(\.playbackMetadataXML))
        }

        return values
    }
}
