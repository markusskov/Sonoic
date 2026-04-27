import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonoicAppleMusicSonosPayloadProbeTests {
    private let probe = SonoicAppleMusicSonosPayloadProbe()

    @Test
    func buildsCatalogCandidateFromLaunchSerial() throws {
        let item = appleMusicSong(catalogID: "1440857781", libraryID: nil)
        let candidates = probe.candidates(
            for: item,
            playbackHint: SonosMusicServicePlaybackHint(
                launchSerials: ["3"],
                trackSerials: ["7"]
            )
        )

        let candidate = try #require(candidates.first { $0.strategy == .catalogHLS })

        #expect(candidate.serialNumber == "3")
        #expect(candidate.uri == "x-sonosapi-hls:song%3a1440857781?sid=204&sn=3")
    }

    @Test
    func buildsLibraryTrackCandidateFromTrackSerial() throws {
        let item = appleMusicSong(catalogID: nil, libraryID: "i.BOVNeOxU6BVbp8")
        let candidates = probe.candidates(
            for: item,
            playbackHint: SonosMusicServicePlaybackHint(
                launchSerials: ["3"],
                trackSerials: ["7"]
            )
        )

        let candidate = try #require(candidates.first { $0.strategy == .libraryTrack })

        #expect(candidate.serialNumber == "7")
        #expect(candidate.uri == "x-sonos-http:librarytrack%3ai.BOVNeOxU6BVbp8.m4p?sid=204&flags=8232&sn=7")
    }

    @Test
    func requiresPlaybackHint() {
        let item = appleMusicSong(catalogID: "1440857781", libraryID: "i.BOVNeOxU6BVbp8")

        #expect(probe.candidates(for: item, playbackHint: nil).isEmpty)
    }

    @Test
    func onlyBuildsSongCandidatesForNow() {
        let album = SonoicSourceItem.appleMusicMetadata(
            id: "1440857780",
            title: "That Low and Lonesome Sound",
            subtitle: "Garrett Kato",
            artworkURL: nil,
            kind: .album,
            origin: .catalogSearch,
            catalogID: "1440857780"
        )
        let candidates = probe.candidates(
            for: album,
            playbackHint: SonosMusicServicePlaybackHint(
                launchSerials: ["3"],
                trackSerials: ["7"]
            )
        )

        #expect(candidates.isEmpty)
    }

    private func appleMusicSong(catalogID: String?, libraryID: String?) -> SonoicSourceItem {
        SonoicSourceItem.appleMusicMetadata(
            id: catalogID ?? libraryID ?? "song",
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            artworkURL: nil,
            kind: .song,
            origin: libraryID == nil ? .catalogSearch : .library,
            catalogID: catalogID,
            libraryID: libraryID
        )
    }
}
