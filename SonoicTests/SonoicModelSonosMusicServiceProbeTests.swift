import Foundation
import Testing
@testable import Sonoic

@Suite("Sonoic model Sonos music service probe")
@MainActor
struct SonoicModelSonosMusicServiceProbeTests {
    @Test("refresh if needed merges fresh observed account evidence into loaded snapshot")
    func refreshIfNeededMergesFreshObservedAccountEvidence() async throws {
        let model = try makeModel()
        model.sonosMusicServiceProbeState = SonosMusicServiceProbeState(
            status: .loaded,
            snapshot: appleMusicSnapshot(accounts: [appleMusicAccount(serialNumber: "3")])
        )
        model.nowPlayingDiagnostics = SonosNowPlayingDiagnostics(
            currentURI: "x-rincon-cpcontainer:1006206cplaylist%3aabc?sid=204&flags=8300&sn=7",
            trackURI: "x-sonos-http:librarytrack%3aabc.m4p?sid=204&flags=8232&sn=5",
            rawDuration: nil,
            rawElapsedTime: nil,
            hasTrackMetadata: false,
            hasSourceMetadata: false,
            usedFallbackSnapshot: false
        )

        await model.refreshSonosMusicServiceProbeIfNeeded()

        let snapshot = try #require(model.sonosMusicServiceProbeState.snapshot)
        let appleMusic = try #require(snapshot.knownServiceRows.first { $0.service == .appleMusic })
        let playbackHint = try #require(appleMusic.playbackHint)

        #expect(model.sonosMusicServiceProbeState.status == .loaded)
        #expect(appleMusic.accounts.map(\.serialNumber) == ["3", "7", "5"])
        #expect(playbackHint.preferredLaunchSerial == "7")
        #expect(playbackHint.trackSerials == ["5"])
    }

    @Test("refresh if needed dedupes fresh evidence into matching status account")
    func refreshIfNeededDedupesFreshEvidenceIntoMatchingStatusAccount() async throws {
        let model = try makeModel()
        model.sonosMusicServiceProbeState = SonosMusicServiceProbeState(
            status: .loaded,
            snapshot: appleMusicSnapshot(accounts: [appleMusicAccount(serialNumber: "7")])
        )
        model.nowPlayingDiagnostics = SonosNowPlayingDiagnostics(
            currentURI: "x-rincon-cpcontainer:1006206cplaylist%3aabc?sid=204&flags=8300&sn=7",
            trackURI: nil,
            rawDuration: nil,
            rawElapsedTime: nil,
            hasTrackMetadata: false,
            hasSourceMetadata: false,
            usedFallbackSnapshot: false
        )

        await model.refreshSonosMusicServiceProbeIfNeeded()

        let snapshot = try #require(model.sonosMusicServiceProbeState.snapshot)
        let appleMusic = try #require(snapshot.knownServiceRows.first { $0.service == .appleMusic })
        let account = try #require(appleMusic.accounts.first)

        #expect(appleMusic.statusTitle == "Ready")
        #expect(appleMusic.accounts.count == 1)
        #expect(account.hasStatusAccount)
        #expect(account.redactedDetail == "sn 7 · user · oauth device · key · current URI")
    }

    private func makeModel() throws -> SonoicModel {
        let suiteName = "SonoicModelSonosMusicServiceProbeTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return SonoicModel(
            settingsStore: SonoicSettingsStore(userDefaults: userDefaults),
            startInitialSonosControlAPICloudRefresh: false
        )
    }

    private func appleMusicSnapshot(
        accounts: [SonosMusicServiceAccountSummary]
    ) -> SonosMusicServiceProbeSnapshot {
        SonosMusicServiceProbeSnapshot(
            observedAt: Date(timeIntervalSince1970: 0),
            serviceListVersion: nil,
            services: [appleMusicDescriptor()],
            accounts: accounts
        )
    }

    private func appleMusicDescriptor() -> SonosMusicServiceDescriptor {
        SonosMusicServiceDescriptor(
            id: "204",
            name: "Apple Music",
            uri: nil,
            secureURI: nil,
            containerType: nil,
            capabilities: nil,
            authPolicy: nil,
            presentationMapURI: nil,
            stringsURI: nil
        )
    }

    private func appleMusicAccount(serialNumber: String) -> SonosMusicServiceAccountSummary {
        SonosMusicServiceAccountSummary(
            serviceType: "52231",
            serialNumber: serialNumber,
            nickname: nil,
            hasUsername: true,
            hasOAuthDeviceID: true,
            hasKey: true
        )
    }
}
