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

    private var observedSonosServiceAccountValues: [SonosMusicServiceObservedValue] {
        var values: [SonosMusicServiceObservedValue] = [
            SonosMusicServiceObservedValue(
                value: nowPlayingDiagnostics.currentURI,
                origin: .currentURI
            ),
            SonosMusicServiceObservedValue(
                value: nowPlayingDiagnostics.trackURI,
                origin: .trackURI
            ),
        ]

        if let favorites = homeFavoritesState.snapshot?.items {
            values.append(contentsOf: favorites.map {
                SonosMusicServiceObservedValue(value: $0.playbackURI, origin: .favoriteURI)
            })
            values.append(contentsOf: favorites.map {
                SonosMusicServiceObservedValue(value: $0.playbackMetadataXML, origin: .favoriteMetadata)
            })
        }

        return values
    }
}
