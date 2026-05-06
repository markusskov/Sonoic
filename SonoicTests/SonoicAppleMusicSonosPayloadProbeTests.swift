import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonoicAppleMusicSonosPayloadProbeTests {
    private let probe = SonoicAppleMusicSonosPayloadProbe()

    @Test
    func buildsCatalogCandidateFromTrackSerial() throws {
        let item = appleMusicSong(catalogID: "1440857781", libraryID: nil)
        let candidates = probe.candidates(
            for: item,
            playbackHint: SonosMusicServicePlaybackHint(
                launchSerials: ["3"],
                trackSerials: ["7"]
            )
        )

        let candidate = try #require(candidates.first { $0.strategy == .catalogHLS })

        #expect(candidate.isUserPlayable)
        #expect(candidate.serialNumber == "7")
        #expect(candidate.uri == "x-sonosapi-hls-static:song%3a1440857781?sid=204&flags=0&sn=7")
        #expect(candidate.metadataXML.contains("<dc:title>Sweet Jane</dc:title>"))
        #expect(candidate.metadataXML.contains("<dc:creator>Garrett Kato</dc:creator>"))
        #expect(candidate.metadataXML.contains("<res protocolInfo=\"sonos.com-http:*:application/x-mpegURL:*\" duration=\"00:03:34\">x-sonosapi-hls-static:song%3a1440857781?sid=204&amp;flags=0&amp;sn=7</res>"))
        #expect(candidate.metadataXML.contains("SA_RINCON52231_X_#Svc52231-0-Token"))

        let payload = try candidate.preparedPlaybackPayload(for: item)
        #expect(payload.title == "Sweet Jane")
        #expect(payload.service == .appleMusic)
        #expect(payload.uri == candidate.uri)
        #expect(payload.metadataXML == candidate.metadataXML)
        #expect(payload.duration == 214)
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

        #expect(!candidate.isUserPlayable)
        #expect(candidate.serialNumber == "7")
        #expect(candidate.uri == "x-sonos-http:librarytrack%3ai.BOVNeOxU6BVbp8.m4p?sid=204&flags=8232&sn=7")
        #expect(candidate.metadataXML.contains("librarytrack:i.BOVNeOxU6BVbp8"))
        #expect(candidate.metadataXML.contains("<res protocolInfo=\"sonos.com-http:*:audio/mp4:*\" duration=\"00:03:34\">x-sonos-http:librarytrack%3ai.BOVNeOxU6BVbp8.m4p?sid=204&amp;flags=8232&amp;sn=7</res>"))
        #expect(candidate.metadataXML.contains("<upnp:class>object.item.audioItem.musicTrack</upnp:class>"))
    }

    @Test
    func queueCandidatePrefersLibraryTrackWhenAvailable() throws {
        let item = appleMusicSong(catalogID: "1440857781", libraryID: "i.BOVNeOxU6BVbp8")

        let candidate = try #require(probe.queueCandidate(
            for: item,
            playbackHint: SonosMusicServicePlaybackHint(
                launchSerials: ["3"],
                trackSerials: ["7"]
            )
        ))

        #expect(candidate.strategy == .libraryTrack)
        #expect(candidate.uri == "x-sonos-http:librarytrack%3ai.BOVNeOxU6BVbp8.m4p?sid=204&flags=8232&sn=7")
    }

    @Test
    func queueCandidateFallsBackToCatalogSongWhenLibraryTrackIsUnavailable() throws {
        let item = appleMusicSong(catalogID: "1440857781", libraryID: nil)

        let candidate = try #require(probe.queueCandidate(
            for: item,
            playbackHint: SonosMusicServicePlaybackHint(
                launchSerials: ["3"],
                trackSerials: ["7"]
            )
        ))

        #expect(candidate.strategy == .catalogHLS)
        #expect(candidate.uri == "x-sonosapi-hls-static:song%3a1440857781?sid=204&flags=0&sn=7")
    }

    @Test
    func buildsPlaylistContainerCandidateFromLaunchSerial() throws {
        let item = SonoicSourceItem.appleMusicMetadata(
            id: "p.abc123",
            title: "Road Songs",
            subtitle: "Apple Music",
            artworkURL: nil,
            kind: .playlist,
            origin: .catalogSearch,
            catalogID: "p.abc123"
        )
        let candidates = probe.candidates(
            for: item,
            playbackHint: SonosMusicServicePlaybackHint(
                launchSerials: ["3"],
                trackSerials: ["7"]
            )
        )

        let candidate = try #require(candidates.first { $0.strategy == .catalogPlaylistContainer })

        #expect(candidate.isUserPlayable)
        #expect(candidate.serialNumber == "3")
        #expect(candidate.uri == "x-rincon-cpcontainer:1006206cplaylist%3ap.abc123?sid=204&flags=8300&sn=3")
        #expect(candidate.metadataXML.contains("<container id=\"playlist:p.abc123\""))
        #expect(candidate.metadataXML.contains("playlist:p.abc123"))
        #expect(candidate.metadataXML.contains("<res protocolInfo=\"x-rincon-cpcontainer:*:*:*\">x-rincon-cpcontainer:1006206cplaylist%3ap.abc123?sid=204&amp;flags=8300&amp;sn=3</res>"))
        #expect(candidate.metadataXML.contains("<upnp:class>object.container.playlistContainer</upnp:class>"))

        let payload = candidate.playbackPayload(for: item)
        #expect(payload.kind == .collection)
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
    func doesNotGuessAlbumCandidatesYet() {
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
            libraryID: libraryID,
            duration: 214
        )
    }
}
