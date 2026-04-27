import Foundation

extension SonoicModel {
    func refreshSonosContentDirectoryProbe() async {
        guard let host = manualSonosHost.sonoicNonEmptyTrimmed else {
            sonosContentDirectoryProbeState = SonosContentDirectoryProbeState(
                status: .failed("Choose a room first."),
                snapshot: nil
            )
            return
        }

        sonosContentDirectoryProbeState = SonosContentDirectoryProbeState(
            status: .loading,
            snapshot: sonosContentDirectoryProbeState.snapshot
        )

        let snapshot = await contentDirectoryProbeClient.fetchProbeSnapshot(host: host)
        sonosContentDirectoryProbeState = SonosContentDirectoryProbeState(
            status: .loaded,
            snapshot: snapshot
        )
    }
}
