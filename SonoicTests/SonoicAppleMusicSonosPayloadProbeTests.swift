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
        #expect(candidate.metadataXML.contains("<dc:title>Sweet Jane</dc:title>"))
        #expect(candidate.metadataXML.contains("<dc:creator>Garrett Kato</dc:creator>"))
        #expect(candidate.metadataXML.contains("SA_RINCON52231_X_#Svc52231-0-Token"))

        let payload = try candidate.preparedPlaybackPayload(for: item)
        #expect(payload.title == "Sweet Jane")
        #expect(payload.service == .appleMusic)
        #expect(payload.uri == candidate.uri)
        #expect(payload.metadataXML == candidate.metadataXML)
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
        #expect(candidate.metadataXML.contains("librarytrack:i.BOVNeOxU6BVbp8"))
        #expect(candidate.metadataXML.contains("<upnp:class>object.item.audioItem.musicTrack</upnp:class>"))
    }

    @Test
    func escapesMetadataXMLValues() throws {
        let item = SonoicSourceItem.appleMusicMetadata(
            id: "1440857781",
            title: "Sweet & Jane",
            subtitle: "Garrett <Kato> • That Low \"Sound\"",
            artworkURL: "https://example.com/art?a=1&b=2",
            kind: .song,
            origin: .catalogSearch,
            catalogID: "1440857781"
        )
        let candidate = try #require(
            probe.candidates(
                for: item,
                playbackHint: SonosMusicServicePlaybackHint(
                    launchSerials: ["3"],
                    trackSerials: []
                )
            ).first
        )

        #expect(candidate.metadataXML.contains("<dc:title>Sweet &amp; Jane</dc:title>"))
        #expect(candidate.metadataXML.contains("<dc:creator>Garrett &lt;Kato&gt;</dc:creator>"))
        #expect(candidate.metadataXML.contains("<upnp:album>That Low &quot;Sound&quot;</upnp:album>"))
        #expect(candidate.metadataXML.contains("https://example.com/art?a=1&amp;b=2"))
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
