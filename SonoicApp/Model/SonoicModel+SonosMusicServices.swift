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
}
